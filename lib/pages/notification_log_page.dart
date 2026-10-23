import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/notification_kind.dart';
import '../utils/pressure_site.dart';
import '../widgets/pressure_snapshot.dart';

/// 지금까지 발송된 알림 목록.
///
/// 폰 알림창에 여러 건이 뭉쳐 오면 어떤 환자의 무슨 알림인지 알 수 없어서,
/// 여기서 한 건씩 펼쳐 본다.
///
/// **종류로 갈라서 본다.** 예전에는 최근 100건을 그냥 보여 줬는데, 식사·배설
/// 누락이 하루에도 여러 건 쌓여서 낙상이 금방 밀려났다. 실제로 10/15 낙상이
/// 158번째에 있어 화면에서 볼 수 없었다. 드물게 오는 것일수록 중요한데
/// 흔한 것에 묻히는 구조였다.
///
/// 열 건씩 이어 붙인다. 한 번에 많이 받아 봐야 낙상은 두세 건이고, 그보다
/// 계속 거슬러 올라갈 수 있는 것이 쓸모 있다.
class NotificationLogPage extends StatefulWidget {
  const NotificationLogPage({super.key});

  @override
  State<NotificationLogPage> createState() => _NotificationLogPageState();
}

/// 무엇만 볼 것인가.
enum _Filter {
  /// 센서가 올린 것 — 낙상·걸터앉음·욕창. 드물게 오지만 제일 중요하다.
  sensor('센서 경보', NotificationKind.criticalKinds),

  /// 스케줄러가 올린 것 — 식사·배설 기록 누락.
  missing('기록 누락', {'meal', 'output'}),

  all('전체', null);

  final String label;

  /// null 이면 거르지 않는다.
  final Set<String>? kinds;

  const _Filter(this.label, this.kinds);
}

class _NotificationLogPageState extends State<NotificationLogPage> {
  /// 한 번에 열 건씩. 낙상은 드물어서 백 건을 받아도 두세 건이고,
  /// 그보다 "계속 거슬러 올라갈 수 있는 것" 이 중요하다.
  static const int _pageSize = 10;

  _Filter _filter = _Filter.sensor;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _end = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _docs.clear();
        _cursor = null;
        _end = false;
      }
    });
    try {
      // 종류로 거르면서 시각으로 정렬하려면 복합 색인이 필요하다.
      // firestore.indexes.json 에 넣어 뒀다.
      Query<Map<String, dynamic>> q =
          FirebaseFirestore.instance.collection('notification_log');
      final kinds = _filter.kinds;
      if (kinds != null) q = q.where('kind', whereIn: kinds.toList());
      q = q.orderBy('sentAt', descending: true).limit(_pageSize);
      if (_cursor != null) q = q.startAfterDocument(_cursor!);

      final snap = await q.get();
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        if (snap.docs.isNotEmpty) _cursor = snap.docs.last;
        // 받은 게 한 쪽보다 적으면 더 없는 것이다.
        if (snap.docs.length < _pageSize) _end = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _switch(_Filter f) {
    if (f == _filter) return;
    setState(() => _filter = f);
    _load(reset: true);
  }

  static const Color mintDark = Color(0xFF16305E);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);

  // 확인 표시. 상태색(주의·위험)과 헷갈리면 안 되므로 초록으로 가른다.
  static const Color ackColor = Color(0xFF15803D);
  static const Color ackBg = Color(0xFFE8F4EC);
  static const Color ackBorder = Color(0xFFC3E2CE);

  /// '20:15'. 확인 시각처럼 같은 줄 안에서 짧게 붙일 때 쓴다.
  String hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// 발송 시각을 '오늘 20:15' / '08.23 20:15' 형태로.
  /// 병동에서는 "언제 갔는지"가 핵심이라 초 단위는 생략한다.
  String formatSentAt(DateTime dt) {
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return '오늘 $hm';

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) return '어제 $hm';

    return '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.day.toString().padLeft(2, '0')} $hm';
  }

  Widget pageHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 18, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF16305E), Color(0xFF22437C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(34),
          bottomRight: Radius.circular(34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x2EFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Expanded 는 남은 폭을 전부 주므로 그 안의 Image 는 width 가
                // 무시되고 헤더 폭만큼 커진다. Align 으로 크기를 묶고 왼쪽에 붙인다.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/icon/nrcarec_wordmark_white.png',
                    width: 142,
                    fit: BoxFit.contain,
                    // 그림을 못 읽어도 화면은 떠야 하므로 글자로 대체한다.
                    errorBuilder: (_, _, _) => const Text(
                      'NRCAREC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '알림 기록',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '지금까지 발송된 알림을 최신순으로 보여줍니다.',
            style: TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// '421호 · 김복순' / '421호 김복순' / '김복순' / '대상 미상'.
  ///
  /// 압력 경보는 센서에 지어 준 이름표만 있고 환자가 누구인지는 모른다.
  /// 그 이름표가 room 에 통째로 들어오므로('421호 김복순'), 이름이 비었다고
  /// '환자 미상'으로 내보내면 정작 아는 것을 버리는 셈이 된다.
  /// 이름이 따로 있는 경보(식사·낙상)만 예전처럼 '호'를 붙여 잇는다.
  String whoText(String room, String name) {
    if (name.isEmpty) return room.isEmpty ? '대상 미상' : room;
    if (room.isEmpty) return name;
    return '$room호 · $name';
  }

  Widget logTile(BuildContext context, String docId, Map<String, dynamic> data) {
    final kind = (data['kind'] ?? '').toString();
    final style = NotificationKind.of(kind);
    final isPressure = kind == 'pressure';

    final sent = data['sentAt'];
    final sentText =
        sent is Timestamp ? formatSentAt(sent.toDate()) : '시각 미상';

    final room = (data['room'] ?? '').toString().trim();
    final name = (data['patientName'] ?? '').toString().trim();
    final who = whoText(room, name);

    final failure = data['failureCount'];
    final failed = failure is int && failure > 0;

    // 누가 언제 확인했는지. 경보가 방치되지 않았다는 근거가 되고,
    // 나중에 "그때 누가 갔었죠"를 물을 때 답이 된다.
    final ackedAt = data['ackedAt'];
    final acked = ackedAt is Timestamp;
    final ackName = (data['ackedByName'] ?? '').toString().trim();
    final ackWho = ackName.isNotEmpty
        ? ackName
        : (data['ackedBy'] ?? '').toString().split('@').first;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderGrey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: style.glyph(size: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sentText,
                      style: const TextStyle(
                        color: textGrey,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  (data['body'] ?? '').toString(),
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 6),
                  Text(
                    '기기 $failure대에 전달 실패',
                    style: const TextStyle(
                      color: dangerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                if (isPressure || acked) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (isPressure) PressureSiteChip(docId: docId),
                      if (acked) _ackChip(ackWho, ackedAt.toDate()),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // 압력 경보에는 그 순간 매트리스 그림이 딸려 온다. 눌러서 크게 볼
          // 수 있다 — 작은 그림으로는 어느 칸인지 가늠하기 어렵다.
          if (isPressure) ...[
            const SizedBox(width: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  showPressureSnapshot(context, docId: docId, who: who),
              child: PressureSnapshot(docId: docId, width: 40, height: 80),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ackChip(String who, DateTime at) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ackBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ackBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 13, color: ackColor),
          const SizedBox(width: 5),
          Text(
            who.isEmpty ? '확인함 · ${hhmm(at)}' : '$who 확인 · ${hhmm(at)}',
            style: const TextStyle(
              color: ackColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderGrey),
      ),
      child: const Column(
        children: [
          Icon(Icons.notifications_none_rounded, size: 44, color: textGrey),
          SizedBox(height: 12),
          Text(
            '아직 발송된 알림이 없습니다.',
            style: TextStyle(
              color: textDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '기록이 빠진 환자가 생기면 여기에 쌓입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget errorState(Object error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '알림 기록을 불러오지 못했습니다',
            style: TextStyle(
              color: dangerColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            '$error',
            style: const TextStyle(
              color: dangerColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 900 ? 640.0 : constraints.maxWidth;

            return RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        pageHeader(context),
                        _filterBar(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                          child: _list(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: _filter == f,
                onSelected: (_) => _switch(f),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _filter == f ? Colors.white : textGrey,
                ),
                selectedColor: mintDark,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: _filter == f ? mintDark : borderGrey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    if (_error != null) return errorState(_error!);
    if (_docs.isEmpty) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return emptyState();
    }
    return Column(
      children: [
        for (final doc in _docs) logTile(context, doc.id, doc.data()),
        const SizedBox(height: 6),
        if (_end)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '${_docs.length}건 — 더 없습니다',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _loading ? null : () => _load(),
              style: OutlinedButton.styleFrom(
                foregroundColor: mintDark,
                side: const BorderSide(color: borderGrey),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _loading ? '불러오는 중…' : '$_pageSize건 더 보기',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}
