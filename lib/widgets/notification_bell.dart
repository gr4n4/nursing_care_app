import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../pages/notification_log_page.dart';
import '../pages/notification_settings_page.dart';
import '../theme/app_colors.dart';
import '../utils/notification_kind.dart';

/// 상단 종 버튼의 동작과 '안 읽음' 표시를 담당한다.
///
/// 버튼 모양은 페이지마다 다르다(대시보드는 아이콘+글씨, 앱은 원형). 그래서
/// 이 클래스는 모양을 그리지 않고, 각 페이지가 자기 버튼에 [unreadDot]을 겹치고
/// [open]을 연결해 쓴다. 모양까지 여기서 그리면 헤더마다 크기가 어긋난다.
///
/// 읽음 시각은 users/{email}.notificationsReadAt 에 남긴다. 기기마다 따로 두면
/// 폰에서 확인해도 대시보드에 점이 남아 헷갈린다.
class NotificationBell {
  const NotificationBell._();

  /// 최근 알림 몇 건만. 전체는 패널의 '전체 보기'로 넘긴다.
  static const int previewCount = 8;

  static Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('notification_log')
      .orderBy('sentAt', descending: true)
      .limit(previewCount);

  static String _timeText(dynamic sentAt) {
    if (sentAt is! Timestamp) return '';
    final dt = sentAt.toDate();
    final now = DateTime.now();
    final hm = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return '오늘 $hm';

    return '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.day.toString().padLeft(2, '0')} $hm';
  }

  static Future<void> open(BuildContext context) async {
    await _markRead();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (ctx) {
        return Align(
          // 종 버튼이 오른쪽 위에 있으므로 패널도 그 아래에 붙인다.
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 68, right: 16, left: 16),
            child: Material(
              color: AppColors.surface,
              elevation: 10,
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
                child: _panelBody(ctx),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _panelBody(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
          child: Row(
            children: [
              const Icon(Icons.notifications_rounded,
                  size: 20, color: AppColors.brand),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '알림',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.inkDim,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        Flexible(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _message(
                  '알림을 불러오지 못했습니다',
                  '${snapshot.error}',
                  isError: true,
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return _message('아직 온 알림이 없습니다', '기록이 빠지면 여기에 쌓입니다.');
              }

              return ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: docs.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.line),
                itemBuilder: (_, i) => _row(docs[i].data()),
              );
            },
          ),
        ),
        const Divider(height: 1, color: AppColors.line),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const NotificationLogPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text('전체 보기'),
              ),
            ),
            Container(width: 1, height: 22, color: AppColors.line),
            Expanded(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('알림 설정'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _message(String title, String body, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.notifications_none_rounded,
            size: 34,
            color: isError ? AppColors.danger : AppColors.inkDim,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isError ? AppColors.danger : AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.inkMid,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _row(Map<String, dynamic> data) {
    final style = NotificationKind.of((data['kind'] ?? '').toString());
    final room = (data['room'] ?? '').toString();
    final name = (data['patientName'] ?? '').toString();
    final who = name.isEmpty
        ? ''
        : (room.isEmpty ? name : '$room호 · $name');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              style.icon,
              size: 18,
              color: style.color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        who.isEmpty ? (data['title'] ?? '알림').toString() : who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeText(data['sentAt']),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.inkDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  (data['body'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMid,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 로그인 계정의 마지막 확인 시각을 지금으로 남긴다.
  static Future<void> _markRead() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(email).set(
        {'notificationsReadAt': Timestamp.now()},
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // 읽음 표시를 못 남겨도 알림 확인 자체는 되어야 하므로 조용히 넘긴다.
    }
  }

  /// 마지막 확인 이후 새 알림이 있으면 빨간 점을 그린다. 없으면 아무것도 안 그린다.
  /// 버튼 위젯을 Stack으로 감싸고 이 위젯을 올려 쓴다.
  static Widget unreadDot({Color borderColor = Colors.white, double size = 9}) {
    final email = FirebaseAuth.instance.currentUser?.email;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notification_log')
          .orderBy('sentAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, logSnap) {
        if (!logSnap.hasData || logSnap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final latest = logSnap.data!.docs.first.data()['sentAt'];
        if (latest is! Timestamp) return const SizedBox.shrink();

        if (email == null) return const SizedBox.shrink();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(email)
              .snapshots(),
          builder: (context, userSnap) {
            final readAt = userSnap.data?.data()?['notificationsReadAt'];
            final unread =
                readAt is! Timestamp || latest.compareTo(readAt) > 0;
            if (!unread) return const SizedBox.shrink();

            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
              ),
            );
          },
        );
      },
    );
  }
}
