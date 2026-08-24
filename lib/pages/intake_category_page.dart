import 'package:flutter/material.dart';

import 'intake_record_page.dart';

/// 환자를 선택하고 "식사량"을 고른 뒤, 섭취 경로별로 4분류를 선택하는 화면.
///  경구식(구강섭취·관급식) / 비경구식(수액) / 수분섭취(음료 포함) / 기타섭취(과일)
/// 각 분류는 IntakeRecordPage 를 해당 section 하나만 보여주는 모드로 연다.
/// (한 화면에 다 쌓지 않아 스크롤이 크게 줄어든다.)
class IntakeCategoryPage extends StatelessWidget {
  final String patientId;
  final String patientName;
  final String room;

  const IntakeCategoryPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.room,
  });

  static const Color mintDark = Color(0xFF0F766E);
  static const Color mintSoft = Color(0xFFE6FAF8);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);

  String get roomText => room.trim().isEmpty
      ? patientName
      : '${room.trim().replaceAll('호', '')}호 · $patientName';

  Future<void> openSection(BuildContext context, IntakeSection section) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IntakeRecordPage(
          patientId: patientId,
          patientName: patientName,
          room: room,
          section: section,
        ),
      ),
    );
  }

  Widget choiceCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color background,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderGrey),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(icon, color: color, size: 36),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: pageBg,
        elevation: 0,
        surfaceTintColor: pageBg,
        foregroundColor: textDark,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 700 ? 560.0 : constraints.maxWidth;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: mintSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFC7EEE9)),
                          ),
                          child: Text(
                            roomText,
                            style: const TextStyle(
                              color: mintDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '어떤 섭취를 기록하시나요?',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '섭취 경로별로 나누어 기록합니다.',
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            choiceCard(
                              label: '경구식',
                              subtitle: '구강섭취 · 관급식',
                              icon: Icons.restaurant_rounded,
                              color: mintDark,
                              background: mintSoft,
                              onTap: () =>
                                  openSection(context, IntakeSection.meal),
                            ),
                            const SizedBox(width: 16),
                            choiceCard(
                              label: '비경구식',
                              subtitle: '수액(IV)',
                              icon: Icons.vaccines_rounded,
                              color: const Color(0xFF7C3AED),
                              background: const Color(0xFFF3E8FF),
                              onTap: () =>
                                  openSection(context, IntakeSection.tubeIv),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            choiceCard(
                              label: '수분섭취',
                              subtitle: '음료 포함',
                              icon: Icons.local_drink_rounded,
                              color: const Color(0xFF2563EB),
                              background: const Color(0xFFE8F0FE),
                              onTap: () =>
                                  openSection(context, IntakeSection.drink),
                            ),
                            const SizedBox(width: 16),
                            choiceCard(
                              label: '기타섭취',
                              subtitle: '과일',
                              icon: Icons.eco_rounded,
                              color: const Color(0xFFEA580C),
                              background: const Color(0xFFFFF1E6),
                              onTap: () =>
                                  openSection(context, IntakeSection.fruit),
                            ),
                          ],
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
}
