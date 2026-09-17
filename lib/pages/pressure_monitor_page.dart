import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/notification_kind.dart';
import '../utils/pressure_site.dart';
import '../widgets/pressure_snapshot.dart';
import '../widgets/pressure_status_view.dart';

/// 욕창 모니터링 — 압력 센서 상태와 최근 경보만 모아 본다.
///
/// 격자를 실시간으로 보거나 임계값·마스크를 고치는 것은 여기서 하지 않는다.
/// 그건 병동 PC 의 압력 대시보드가 할 일이고, 실시간 격자는 1.5초마다 값이
/// 바뀌어 Firestore 로 실어 나를 수 있는 양이 아니다(센서 8대면 하루 46만 건,
/// 무료 한도의 23배). 여기는 "지금 괜찮은가"와 "무슨 일이 있었나"를 본다.
class PressureMonitorPage extends StatelessWidget {
  const PressureMonitorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('욕창 모니터링'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 900 ? 640.0 : constraints.maxWidth;
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _card(
                          title: '센서 상태',
                          child: const PressureStatusView(),
                        ),
                        const SizedBox(height: 14),
                        _card(
                          title: '최근 경보',
                          child: const _RecentAlerts(),
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

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: NotificationKind.of('pressure')
                      .glyph(size: 22, tint: AppColors.brand),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts();

  @override
  Widget build(BuildContext context) {
    // 종류로 거르면서 시각으로 정렬하면 복합 색인이 필요하고, 색인이 만들어질
    // 때까지 화면이 통째로 비어 보인다. 정렬만 걸고 종류는 받아서 거른다.
    final query = FirebaseFirestore.instance
        .collection('notification_log')
        .orderBy('sentAt', descending: true)
        .limit(60);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _hint('경보를 불러오지 못했습니다.', danger: true);
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data!.docs
            .where((d) => (d.data()['kind'] ?? '') == 'pressure')
            .toList();

        if (docs.isEmpty) {
          return _hint('아직 욕창 경보가 없습니다.');
        }

        return Column(
          children: [
            for (var i = 0; i < docs.length; i++) ...[
              if (i > 0)
                const Divider(height: 22, thickness: 1, color: AppColors.line),
              _row(context, docs[i].id, docs[i].data()),
            ],
          ],
        );
      },
    );
  }

  Widget _hint(String text, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: TextStyle(
          color: danger ? AppColors.danger : AppColors.inkDim,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String docId, Map<String, dynamic> data) {
    final sent = data['sentAt'];
    final when = sent is Timestamp
        ? '${sent.toDate().month.toString().padLeft(2, '0')}.'
            '${sent.toDate().day.toString().padLeft(2, '0')} '
            '${sent.toDate().hour.toString().padLeft(2, '0')}:'
            '${sent.toDate().minute.toString().padLeft(2, '0')}'
        : '시각 미상';
    final who = (data['room'] ?? '').toString().trim();
    final acked = data['ackedAt'] != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      who.isEmpty ? '대상 미상' : who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    when,
                    style: const TextStyle(
                      color: AppColors.inkMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                (data['body'] ?? '').toString(),
                style: const TextStyle(
                  color: AppColors.inkMid,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  PressureSiteChip(docId: docId),
                  if (!acked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warnBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFEBD6B4)),
                      ),
                      child: const Text(
                        '확인 안 함',
                        style: TextStyle(
                          color: AppColors.warn,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showPressureSnapshot(
            context,
            docId: docId,
            who: who.isEmpty ? '압력 분포' : who,
          ),
          child: PressureSnapshot(docId: docId, width: 40, height: 80),
        ),
      ],
    );
  }
}
