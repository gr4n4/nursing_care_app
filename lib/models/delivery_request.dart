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

/// 로봇이 스스로 적는 상태. `robot_state/current` 문서 하나다.
///
/// 앱은 읽기만 한다 — Firestore 규칙에서도 쓰기가 막혀 있다.
class RobotState {
  const RobotState._();

  /// 이보다 오래된 신호면 끊긴 것으로 본다.
  ///
  /// 로봇은 멈춰 있을 때도 60초마다 살아있음 신호를 쓴다. 그래서 한 번
  /// 빠뜨리는 것은 넘겨 주고, 두 번 연속 빠뜨리면 끊긴 것으로 센다.
  /// 이 값은 로봇 쪽 브릿지의 신호 주기와 짝이다 — 주기가 바뀌면 같이 고친다.
  static const Duration deadline = Duration(minutes: 2);

  /// 로봇 신호가 끊겼는가.
  ///
  /// `online` 과 다른 것을 잡는다. `online: false` 는 로봇이 직접 쓴 값이라
  /// '곱게 꺼졌다'는 뜻이고, 여기서 보는 것은 **아무 말도 없이 사라진** 쪽이다.
  /// 전원이 빠지거나 네트워크가 끊기면 마지막 값이 화면에 그대로 굳는다.
  ///
  /// 모르는 것은 끊긴 것으로 세지 않는다. [updatedAt] 이 없으면 false 고,
  /// 미래 시각이어도 false 다 — 이 PC 시계가 뒤로 틀어져 있을 때 멀쩡한
  /// 로봇을 죽은 것으로 보이게 하면 안 된다.
  static bool isStale(DateTime? updatedAt, {DateTime? now}) {
    if (updatedAt == null) return false;
    return (now ?? DateTime.now()).difference(updatedAt) > deadline;
  }
}

/// 로봇이 왜 못 갔는지를 간호사가 읽는 말로 바꾼다.
///
/// 로봇이 함께 보내는 failReason 은 "'적재' 주행 실패" 처럼 내부 목적지
/// 이름이 그대로 새어 나온 말이다. 로그를 볼 때는 쓸모가 있지만, 간호사가
/// 읽고 **무엇을 해야 하는지** 는 알 수 없다. 그래서 코드로 받아 여기서
/// 문구를 만든다.
class DeliveryFail {
  const DeliveryFail._();

  /// 로봇과 맞춰 둔 코드표. 여기 없는 코드가 와도 화면이 비면 안 된다.
  static const Map<String, String> _notes = {
    'room_not_servable': '로봇이 갈 수 없는 호실입니다. 다른 방법으로 전달해 주세요.',
    'waypoint_missing': '로봇 자리 설정이 빠졌습니다. 로봇 담당자를 불러 주세요.',
    'nav_failed_loading': '로봇이 물품을 실으러 가다 멈췄습니다. 널스스테이션을 확인해 주세요.',
    'nav_failed_room': '로봇이 병실로 가다 멈췄습니다. 복도를 확인해 주세요.',
    'nav_timeout': '로봇이 제 시간에 닿지 못했습니다. 복도를 확인해 주세요.',
    'goal_rejected': '로봇이 목적지를 받지 못했습니다. 로봇 담당자를 불러 주세요.',
    'nav_failed_return': '물품은 전달됐습니다. 로봇이 대기 자리로 돌아가지 못했습니다.',
  };

  /// [code] 를 문구로. 모르는 코드면 로봇이 적은 [reason] 이라도 보여 준다 —
  /// 뜻을 모르는 글이라도 아무 말 없는 것보다는 낫다.
  static String describe(String code, String reason) {
    final note = _notes[code];
    if (note != null) return note;
    if (reason.isNotEmpty) return '로봇이 멈췄습니다 ($reason). 복도를 확인해 주세요.';
    return '로봇이 멈췄습니다. 복도를 확인해 주세요.';
  }
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

  /// 물품을 전달했는가: `done` / `failed`. 로봇만 쓴다.
  ///
  /// 복귀 성패와 갈라 놓은 값이다. 예전에는 `status` 하나에 둘을 겹쳐 써서,
  /// 물건을 다 전달하고 돌아오다 멈추면 배송 전체가 실패로 남았다. 간호사
  /// 입장에서는 성공인데 기록은 실패라, 그대로 두면 성공률이 실제보다
  /// 나쁘게 나온다.
  ///
  /// **로봇이 아직 안 쓸 수 있다.** 비어 있으면 예전처럼 `status` 로 읽는다.
  final String deliveryResult;

  /// 대기 자리로 돌아갔는가: `closed` / `failed`. 로봇만 쓴다.
  ///
  /// `failed` 라도 물품은 전달이 끝난 것이다. 복도에 로봇이 서 있는 것은
  /// 그 배송 건의 문제가 아니라 로봇의 문제라, 요청 목록이 아니라
  /// `robot_state/current` 의 needsAttention 으로 사람을 부른다.
  final String returnResult;

  /// 실패 종류. 간호사에게 보일 문구는 앱이 만든다 —
  /// [failReason] 은 로봇이 로그용으로 적는 자유문구라 화면에 쓰지 않는다.
  final String failCode;

  final String returnFailCode;
  final String returnFailReason;

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
    this.deliveryResult = '',
    this.returnResult = '',
    this.failCode = '',
    this.returnFailCode = '',
    this.returnFailReason = '',
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
      deliveryResult: (d['deliveryResult'] ?? '').toString(),
      returnResult: (d['returnResult'] ?? '').toString(),
      failCode: (d['failCode'] ?? '').toString(),
      returnFailCode: (d['returnFailCode'] ?? '').toString(),
      returnFailReason: (d['returnFailReason'] ?? '').toString(),
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

  /// 로봇이 대기 자리로 돌아가지 못했는가.
  ///
  /// 이때 `status` 는 `closed` 로 온다. 물품은 전달이 끝났으니 그 건은 끝난
  /// 일이 맞고, 못 돌아간 것은 따로 드러내야 한다. 이 값을 안 보면 복도에
  /// 로봇이 서 있는데 화면에는 '완료' 로만 보인다.
  bool get robotStranded => returnResult == 'failed';

  /// 물품이 전달됐는가.
  ///
  /// 로봇이 새 필드를 쓰기 전에는 `status` 로 읽는다. 이 갈래가 없으면
  /// 앱을 먼저 배포할 수 없다 — 로봇만 먼저 고치면 복귀 실패가 '완료' 로
  /// 보여, 지금 있는 신호마저 사라진다.
  bool get deliveredOk => deliveryResult.isNotEmpty
      ? deliveryResult == 'done'
      : (status == DeliveryStatus.done || status == DeliveryStatus.closed);

  /// 화면에 쓸 끝맺음 말.
  ///
  /// 새 필드가 하나도 없으면 예전과 똑같은 글자가 나온다.
  String get resultLabel {
    if (status == DeliveryStatus.canceled) return '취소됨';
    if (deliveryResult.isEmpty && returnResult.isEmpty) {
      return DeliveryStatus.label(status);
    }
    if (deliveryResult == 'failed') return '배송 실패';
    if (robotStranded) return '전달 완료 · 로봇 복귀 실패';
    return DeliveryStatus.label(status);
  }

  /// 간호사에게 보일 실패 설명. 없으면 null.
  ///
  /// 로봇이 적는 failReason("'적재' 주행 실패")은 쓰지 않는다. 내부 목적지
  /// 이름이 그대로 새어 나온 말이라, 간호사가 무엇을 해야 하는지 알 수 없다.
  String? get failNote {
    if (robotStranded) {
      return '물품은 전달됐습니다. 로봇이 대기 자리로 돌아가지 못했습니다.';
    }
    if (deliveryResult == 'failed' || status == DeliveryStatus.failed) {
      return DeliveryFail.describe(failCode, failReason);
    }
    return null;
  }
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
