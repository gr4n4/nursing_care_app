import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'patient_day_page.dart';

/// 퇴원한 환자 보관함.
///
/// 퇴원해도 기록은 남아야 한다. 그 사람이 있던 동안의 식사·배설·경보는
/// 나중에 "그때 어땠냐" 를 묻는 자리에서 쓰인다.
///
/// 그렇다고 본 목록에 두면 지금 돌봐야 하는 사람이 묻힌다. 실제로 다섯
/// 명을 보는 병동에서 아홉 줄이 떴다. 그래서 여기로 뺀다.
///
/// **사람이 바뀌면 환자를 새로 만들어야 한다.** 이름만 고쳐 쓰면 한 문서에
/// 여러 사람의 기록이 섞인다 — 2026-10 에 실제로 그래서 421호 문서 하나에
/// 세 사람 기록이 들어가 있었고, 날짜로 갈라 떼어내야 했다.
class DischargedPatientsPage extends StatelessWidget {
  const DischargedPatientsPage({super.key});

  /// 퇴원한 사람만. 활성 환자와 같은 컬렉션이라 `isActive` 로 가른다.
  ///
  /// 한 필드 조회라 복합 색인이 필요 없다. 퇴원자는 늘어나기만 하지만
  /// 병동 하나에서 수백 명이 될 일은 없다.
  static Query<Map<String, dynamic>> get _query => FirebaseFirestore.instance
      .collection('patients')
      .where('isActive', isEqualTo: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('퇴원 환자'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _query.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _note(
                Icons.error_outline_rounded,
                '불러오지 못했습니다',
                '${snap.error}',
                AppColors.danger,
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs.toList()
              ..sort((a, b) {
                // 최근에 나간 사람이 위로. 퇴원일이 없는 옛 자료는 맨 아래.
                final at = dischargedAt(a.data());
                final bt = dischargedAt(b.data());
                if (at == null && bt == null) {
                  return (a.data()['name'] ?? '')
                      .toString()
                      .compareTo((b.data()['name'] ?? '').toString());
                }
                if (at == null) return 1;
                if (bt == null) return -1;
                return bt.compareTo(at);
              });

            if (docs.isEmpty) {
              return _note(
                Icons.inbox_rounded,
                '퇴원한 환자가 없습니다',
                '환자를 퇴원 처리하면 여기에 모입니다. 기록은 그대로 남습니다.',
                AppColors.inkDim,
              );
            }

            return LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth >= 900 ? 720.0 : c.maxWidth;
                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: w),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${docs.length}명 — 기록은 그대로 남아 있습니다.',
                              style: const TextStyle(
                                color: AppColors.inkMid,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final d in docs) _Card(doc: d),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// 퇴원일. 대시보드 토글은 `hiddenAt` 으로, 기록을 갈라 만든 쪽은
  /// `archivedAt` 으로 적는다. 둘 다 본다.
  static DateTime? dischargedAt(Map<String, dynamic> d) {
    for (final k in ['archivedAt', 'hiddenAt', 'updatedAt']) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }

  Widget _note(IconData icon, String title, String body, Color tint) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: tint),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMid,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _Card({required this.doc});

  static int _age(dynamic birthDate) {
    final s = (birthDate ?? '').toString();
    final born = DateTime.tryParse(s);
    if (born == null) return 0;
    final now = DateTime.now();
    var a = now.year - born.year;
    if (now.month < born.month ||
        (now.month == born.month && now.day < born.day)) {
      a--;
    }
    return a;
  }

  Future<void> _restore(BuildContext context) async {
    final name = (doc.data()['name'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('다시 입원으로 되돌릴까요'),
        content: Text(
          '$name 님을 환자 목록으로 되돌립니다.\n'
          '같은 분이 다시 들어오신 경우에만 쓰세요 — 다른 분이면 '
          '새로 등록해야 기록이 섞이지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('되돌리기'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await doc.reference.update({'isActive': true});
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final name = (d['name'] ?? '이름 없음').toString();
    final room = (d['room'] ?? '').toString();
    final at = DischargedPatientsPage.dischargedAt(d);
    final note = (d['note'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // 눌러서 그 사람 기록을 연다. 기록을 보려고 되돌릴 필요는 없어야 한다.
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientDayPage(
              patientId: doc.id,
              name: name,
              room: room,
              age: _age(d['birthDate']),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (room.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.pageBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              room,
                              style: const TextStyle(
                                color: AppColors.inkMid,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      at == null
                          ? '퇴원일 기록 없음'
                          : '퇴원 ${at.year}.${at.month.toString().padLeft(2, '0')}'
                              '.${at.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: AppColors.inkDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        style: const TextStyle(
                          color: AppColors.inkDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _restore(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('되돌리기'),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.inkDim, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
