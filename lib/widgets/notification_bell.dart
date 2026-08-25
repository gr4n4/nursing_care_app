import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../pages/notification_log_page.dart';
import '../pages/notification_settings_page.dart';
import '../theme/app_colors.dart';

/// 상단 종 모양 버튼. 누르면 최근 알림이 바로 아래로 펼쳐진다.
///
/// 전에는 알림 설정 화면까지 들어가야 기록을 볼 수 있었다. 알림은 "왔는지 확인"이
/// 잦은 일이라 메인 화면에서 한 번에 닿아야 한다. 설정은 이 패널 아래쪽 링크로 옮겼다.
class NotificationBell extends StatelessWidget {
  /// 헤더 배경이 어두우면(그라데이션 헤더) 아이콘을 흰색으로 쓴다.
  final bool onDarkHeader;

  const NotificationBell({super.key, this.onDarkHeader = false});

  /// 최근 알림 몇 건만. 전체는 패널의 '전체 보기'로 넘긴다.
  static const int previewCount = 8;

  static Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('notification_log')
      .orderBy('sentAt', descending: true)
      .limit(previewCount);

  String _timeText(dynamic sentAt) {
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

  void _openPanel(BuildContext context) {
    showDialog<void>(
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

  Widget _panelBody(BuildContext ctx) {
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

  Widget _message(String title, String body, {bool isError = false}) {
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

  Widget _row(Map<String, dynamic> data) {
    final isMeal = (data['kind'] ?? '').toString() == 'meal';
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
              color: isMeal ? AppColors.brandSoft : const Color(0xFFE3EEFB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMeal ? Icons.restaurant_rounded : Icons.water_drop_rounded,
              size: 18,
              color: isMeal ? AppColors.brand : AppColors.fluid,
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

  @override
  Widget build(BuildContext context) {
    final iconColor = onDarkHeader ? Colors.white : AppColors.inkMid;

    // 오늘 온 알림이 있으면 종에 점을 찍어 "볼 게 있다"를 알린다.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query.snapshots(),
      builder: (context, snapshot) {
        var hasToday = false;
        if (snapshot.hasData) {
          final now = DateTime.now();
          for (final d in snapshot.data!.docs) {
            final ts = d.data()['sentAt'];
            if (ts is! Timestamp) continue;
            final dt = ts.toDate();
            if (dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day) {
              hasToday = true;
              break;
            }
          }
        }

        return Tooltip(
          message: '알림',
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openPanel(context),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 22, color: iconColor),
                  if (hasToday)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: onDarkHeader
                                ? AppColors.brand
                                : AppColors.surface,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
