import 'package:cloud_firestore/cloud_firestore.dart';

/// 물품 배송 요청 한 건.
///
/// 로봇 쪽 브릿지(colcon_ws_jy/scripts/nrcarec_bridge.py)와 짝을 이룬다.
/// 상태 이름과 흐름을 양쪽이 똑같이 알고 있어야 하므로, 값을 바꿀 때는
/// 반드시 브릿지의 ACTIONS 표도 함께 고쳐야 한다.
///
///     requested    간호사가 앱에서 요청함
///        ↓ 널스스테이션에서 [수락]
///     accepted     ──▶ 로봇: 널스스테이션으로 이동 ──▶ at_loading
///        ↓ 물품 싣고 [출발]
///     delivering   ──▶ 로봇: 병실로 이동           ──▶ delivered
///        ↓ [수령 확인]
///     done         ──▶ 로봇: 대기 자리로 복귀       ──▶ closed
///
/// 사람이 누르는 것은 accepted / delivering / done / canceled 뿐이다.
/// at_loading·delivered·closed 는 로봇이 실제로 도착했을 때만 찍혀야 하는
/// 값이라, Firestore 보안 규칙에서도 사람이 못 쓰게 막아 두었다.
class DeliveryStatus {
  const DeliveryStatus._();

  static const requested = 'requested';
  static const accepted = 'accepted';
  static const atLoading = 'at_loading';
  static const delivering = 'delivering';
  static const delivered = 'delivered';
  static const done = 'done';
  static const closed = 'closed';
  static const canceled = 'canceled';
  static const failed = 'failed';

  /// 아직 처리 중인 것들. 배차 화면 목록에 남는다.
  static const active = <String>{
    requested, accepted, atLoading, delivering, delivered, done,
  };

  /// 더 손댈 게 없는 것들.
  static const finished = <String>{closed, canceled, failed};

  /// 화면에 보여줄 이름. 간호사가 읽는 말이라 상태값 그대로 쓰지 않는다.
  static String label(String s) => switch (s) {
        requested => '요청 접수',
        accepted => '로봇 오는 중',
        atLoading => '적재 대기',
        delivering => '배송 중',
        delivered => '도착 · 수령 대기',
        done => '복귀 중',
        closed => '완료',
        canceled => '취소됨',
        failed => '실패',
        _ => s,
      };

  /// 지금 사람이 눌러야 할 다음 동작. 없으면 null(로봇이 움직이는 중).
  ///
  /// 로봇이 일하는 동안 버튼을 눌러 봐야 아무 일도 안 나므로,
  /// 아예 버튼을 내려 "지금은 기다리는 때"임을 보이게 한다.
  static ({String next, String label})? nextAction(String s) => switch (s) {
        requested => (next: accepted, label: '수락'),
        atLoading => (next: delivering, label: '물품 실었음 · 출발'),
        delivered => (next: done, label: '수령 확인'),
        _ => null,
      };
}

class DeliveryRequest {
  final String id;
  final String room;
  final List<DeliveryItem> items;
  final String note;
  final String status;
  final DateTime? createdAt;

  /// 요청한 계정. 지금은 간호과가 공용 계정 하나를 쓰고 있어 화면에 띄우지
  /// 않지만, 나중에 개인 계정으로 바뀌면 그때부터 의미가 생기므로 남겨 둔다.
  final String createdBy;

  final String failReason;

  /// 잠깐 멈춰 달라는 표시.
  ///
  /// 상태와 따로 두는 이유: 멈춤은 어디까지 갔는지를 바꾸지 않는다. 병실로
  /// 가던 중에 멈췄다가 다시 보내면 하던 일을 이어서 해야지, 처음부터 다시
  /// 하면 안 된다. 상태로 표현하면 그 '어디까지 갔는지'가 지워진다.
  ///
  /// 로봇 쪽 브릿지가 이 값을 보고 멈추고 다시 간다.
  final bool paused;

  const DeliveryRequest({
    required this.id,
    required this.room,
    required this.items,
    required this.status,
    this.note = '',
    this.createdAt,
    this.createdBy = '',
    this.failReason = '',
    this.paused = false,
  });

  factory DeliveryRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? <String, dynamic>{};
    return DeliveryRequest(
      id: doc.id,
      room: (d['room'] ?? '').toString(),
      items: (d['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DeliveryItem.fromMap)
          .toList(),
      note: (d['note'] ?? '').toString(),
      status: (d['status'] ?? DeliveryStatus.requested).toString(),
      createdAt: _parseTime(d['createdAt']),
      createdBy: (d['createdBy'] ?? '').toString(),
      failReason: (d['failReason'] ?? '').toString(),
      paused: d['paused'] == true,
    );
  }

  /// 로봇이 지금 움직이고 있어야 하는 상태인가.
  /// 이때만 '일시정지'와 '취소'가 뜻을 갖는다. 복귀 중(done)은 뺀다 —
  /// 물품은 이미 전달됐고, 돌아가는 것을 멈춰 세울 이유가 없다.
  bool get isMoving =>
      status == DeliveryStatus.accepted || status == DeliveryStatus.delivering;

  /// 브릿지는 ISO 8601 문자열로, 앱은 Timestamp 로 쓴다. 둘 다 받는다.
  static DateTime? _parseTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  String get itemsText => items.isEmpty
      ? '(품목 없음)'
      : items.map((e) => e.display).join(', ');

  bool get isActive => DeliveryStatus.active.contains(status);
}

class DeliveryItem {
  final String name;
  final int qty;

  const DeliveryItem({required this.name, this.qty = 1});

  factory DeliveryItem.fromMap(Map<String, dynamic> m) => DeliveryItem(
        name: (m['name'] ?? '').toString(),
        qty: (m['qty'] is num) ? (m['qty'] as num).toInt() : 1,
      );

  Map<String, dynamic> toMap() => {'name': name, 'qty': qty};

  String get display => qty > 1 ? '$name $qty개' : name;
}
