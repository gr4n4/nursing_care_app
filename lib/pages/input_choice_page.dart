import 'package:flutter/material.dart';

import 'output_record_page.dart';
import 'intake_category_page.dart';

/// 환자를 선택한 뒤 "무엇을 입력하시나요?" (식사량 / 배설량)를 고르는 화면.
/// 식사량 → IntakeRecordPage(간호사 모드), 배설량 → OutputRecordPage.
class InputChoicePage extends StatelessWidget {
  final String patientId;
  final String patientName;
  final String room;

  const InputChoicePage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.room,
  });

  static const Color mint = Color(0xFF16305E);
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);

  String get roomText => room.trim().isEmpty
      ? patientName
      : '${room.trim().replaceAll('호', '')}호 · $patientName';

  Future<void> openMeal(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IntakeCategoryPage(
          patientId: patientId,
          patientName: patientName,
          room: room,
        ),
      ),
    );
  }

  Future<void> openOutput(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutputRecordPage(
          patientId: patientId,
          patientName: patientName,
          room: room,
        ),
      ),
    );
  }

  Widget choiceCard({
    required BuildContext context,
    required String label,
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
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(icon, color: color, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
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
            final maxWidth = constraints.maxWidth >= 700 ? 560.0 : constraints.maxWidth;

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
                            border: Border.all(color: const Color(0xFFC3D5EE)),
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
                          '무엇을 입력하시나요?',
                          style: TextStyle(
                            color: textDark,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '기록할 항목을 선택해주세요.',
                          style: TextStyle(
                            color: textGrey,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            choiceCard(
                              context: context,
                              label: '식사량',
                              icon: Icons.restaurant_rounded,
                              color: mintDark,
                              background: mintSoft,
                              onTap: () => openMeal(context),
                            ),
                            const SizedBox(width: 16),
                            choiceCard(
                              context: context,
                              label: '배설량',
                              icon: Icons.water_drop_rounded,
                              color: const Color(0xFF2563EB),
                              background: const Color(0xFFE8F0FE),
                              onTap: () => openOutput(context),
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
