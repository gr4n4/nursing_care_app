import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 지금까지 발송된 기록 누락 알림 목록.
///
/// 폰 알림창에 여러 건이 뭉쳐 오면 어떤 환자의 무슨 알림인지 알 수 없어서,
/// 여기서 한 건씩 펼쳐 본다. 스케줄러(scripts/notify.js)가 발송할 때마다
/// notification_log 에 남긴 기록을 최신순으로 보여준다.
class NotificationLogPage extends StatelessWidget {
  const NotificationLogPage({super.key});

  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);

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
                child: Image.asset(
                  'assets/icon/nrcarec_wordmark_white.png',
                  width: 168,
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

  Widget logTile(Map<String, dynamic> data) {
    final kind = (data['kind'] ?? '').toString();
    final isMeal = kind == 'meal';

    final sent = data['sentAt'];
    final sentText =
        sent is Timestamp ? formatSentAt(sent.toDate()) : '시각 미상';

    final room = (data['room'] ?? '').toString();
    final name = (data['patientName'] ?? '').toString();
    final who = name.isEmpty
        ? '환자 미상'
        : (room.isEmpty ? name : '$room호 · $name');

    final failure = data['failureCount'];
    final failed = failure is int && failure > 0;

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
              color: isMeal ? mintSoft : const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isMeal ? Icons.restaurant_rounded : Icons.water_drop_rounded,
              color: isMeal ? mintDark : const Color(0xFF2563EB),
              size: 22,
            ),
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
              ],
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
    // 최근 100건만. 병동에서 거슬러 볼 만한 범위이고 읽기 비용도 아낀다.
    final query = FirebaseFirestore.instance
        .collection('notification_log')
        .orderBy('sentAt', descending: true)
        .limit(100);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 900 ? 640.0 : constraints.maxWidth;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pageHeader(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: query.snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return errorState(snapshot.error!);
                            }
                            if (!snapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final docs = snapshot.data!.docs;
                            if (docs.isEmpty) return emptyState();

                            return Column(
                              children: [
                                for (final doc in docs)
                                  logTile(doc.data() as Map<String, dynamic>),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
