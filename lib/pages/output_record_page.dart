import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/care_date.dart';
import '../utils/feedback.dart';
import 'login_page.dart';

class OutputRecordPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String room;

  const OutputRecordPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.room,
  });

  @override
  State<OutputRecordPage> createState() => _OutputRecordPageState();
}

class _OutputRecordPageState extends State<OutputRecordPage> {
  static const Color mint = Color(0xFF16305E);
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color blueColor = Color(0xFF2563EB);

  final TextEditingController urineAmountController = TextEditingController();
  final TextEditingController stoolAmountController = TextEditingController();
  final TextEditingController memoController = TextEditingController();

  String urineType = 'natural';
  bool hasStool = false;
  bool isSaving = false;
  int refreshKey = 0;

  String get todayString => careDateKey(DateTime.now());

  String get displayDateString => careDateDisplay(DateTime.now());

  String get nowTimeString => wallClockTime(DateTime.now());

  String cleanRoom(String value) {
    return value.replaceAll('호', '').trim();
  }

  int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double contentMaxWidth(double screenWidth) {
    if (screenWidth >= 900) return 660;
    return screenWidth;
  }

  void adjustAmount(TextEditingController controller, int delta) {
    final current = int.tryParse(controller.text.trim()) ?? 0;
    final next = (current + delta).clamp(0, 100000);
    setState(() {
      controller.text = next.toString();
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    });
  }

  String getUrineTypeLabel(String value) {
    switch (value) {
      case 'natural':
        return '자연배뇨';
      case 'catheter':
        return '카테타';
      case 'incontinence':
        return '실금';
      case 'diaper':
        return '기저귀';
      default:
        return value;
    }
  }

  IconData getUrineTypeIcon(String value) {
    switch (value) {
      case 'natural':
        return Icons.water_drop_rounded;
      case 'catheter':
        return Icons.medical_services_rounded;
      case 'incontinence':
        return Icons.child_friendly_rounded;
      case 'diaper':
        return Icons.baby_changing_station;
      default:
        return Icons.water_drop_rounded;
    }
  }

  Future<void> saveOutput() async {
    if (isSaving) return;

    final urineAmount = int.tryParse(urineAmountController.text.trim()) ?? 0;
    final stoolAmount =
        hasStool ? int.tryParse(stoolAmountController.text.trim()) ?? 0 : 0;

    if (urineAmount <= 0 && !hasStool) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('배뇨량 또는 배변 여부를 입력해주세요')),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    final bool isDiaper = urineType == 'diaper';
    final naturalUrine = urineType == 'natural' ? urineAmount : 0;
    final catheterUrine = urineType == 'catheter' ? urineAmount : 0;
    final incontinenceUrine = urineType == 'incontinence' ? urineAmount : 0;
    final diaperGram = isDiaper ? urineAmount : 0;

    try {
      await FirebaseFirestore.instance.collection('output_records').add({
        'patientId': widget.patientId,
        'patientName': widget.patientName,
        'room': cleanRoom(widget.room),
        'date': todayString,
        'time': nowTimeString,
        'urineType': urineType,
        'urineTypeLabel': getUrineTypeLabel(urineType),
        'urineAmount': urineAmount,
        // 기저귀는 무게(g), 그 외 배뇨는 ml
        'urineUnit': isDiaper ? 'g' : 'ml',
        'naturalUrine': naturalUrine,
        'catheterUrine': catheterUrine,
        'incontinenceUrine': incontinenceUrine,
        'urineDiaperGram': diaperGram,
        'stoolYn': hasStool,
        'stoolAmount': stoolAmount,
        'stoolUnit': hasStool ? 'g' : '',
        'stoolCount': hasStool ? 1 : 0,
        'totalOutput': urineAmount,
        'memo': memoController.text.trim(),
        'createdAt': Timestamp.now(),

        // 대시보드 집계용: 기저귀는 diaper_weight, urineMl에는 포함하지 않는다.
        'urineMethod': isDiaper ? 'diaper_weight' : urineType,
        'urineMethodLabel': getUrineTypeLabel(urineType),
        'urineMl': isDiaper ? 0 : urineAmount,
      });

      if (!mounted) return;

      showSaveSuccess(context, message: '배설 기록이 저장되었습니다.');

      urineAmountController.clear();
      stoolAmountController.clear();
      memoController.clear();

      setState(() {
        urineType = 'natural';
        hasStool = false;
        refreshKey++;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });
    }
  }

  Future<void> deleteOutputRecord(String docId) async {
    await FirebaseFirestore.instance
        .collection('output_records')
        .doc(docId)
        .delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('배설 기록 삭제 완료')),
    );

    setState(() {
      refreshKey++;
    });
  }

  Future<Map<String, dynamic>> loadMealSummary() async {
    final mealSnapshot = await FirebaseFirestore.instance
        .collection('meal_records')
        .where('patientId', isEqualTo: widget.patientId)
        .where('date', isEqualTo: todayString)
        .get();

    final waterSnapshot = await FirebaseFirestore.instance
        .collection('water_records')
        .where('patientId', isEqualTo: widget.patientId)
        .where('date', isEqualTo: todayString)
        .get();

    int totalFoodGram = 0;
    int totalSoupMl = 0;
    int totalWaterMl = 0;

    bool breakfastRecorded = false;
    bool lunchRecorded = false;
    bool dinnerRecorded = false;

    for (final doc in mealSnapshot.docs) {
      final data = doc.data();

      totalFoodGram += toInt(data['totalFoodGram']);
      totalSoupMl += toInt(data['totalFluidMl']);

      final mealType = data['mealType'];
      if (mealType == 'breakfast') breakfastRecorded = true;
      if (mealType == 'lunch') lunchRecorded = true;
      if (mealType == 'dinner') dinnerRecorded = true;
    }

    for (final doc in waterSnapshot.docs) {
      final data = doc.data();
      totalWaterMl += toInt(data['amountMl']);
    }

    return {
      'totalFoodGram': totalFoodGram,
      'totalSoupMl': totalSoupMl,
      'totalWaterMl': totalWaterMl,
      'totalFluidInputMl': totalSoupMl + totalWaterMl,
      'breakfastRecorded': breakfastRecorded,
      'lunchRecorded': lunchRecorded,
      'dinnerRecorded': dinnerRecorded,
    };
  }

  InputDecoration inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: mintDark, width: 1.5),
      ),
    );
  }

  Widget sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    Color color = Colors.white,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
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
      child: child,
    );
  }

  Widget safeButton({
    required String label,
    required VoidCallback? onTap,
    required Color backgroundColor,
    required Color textColor,
    Color? borderColor,
    IconData? icon,
    double height = 44,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
    bool expand = false,
  }) {
    final bool disabled = onTap == null;

    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: Container(
        width: expand ? double.infinity : null,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFE5E7EB) : backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: disabled
                ? const Color(0xFFE5E7EB)
                : (borderColor ?? backgroundColor),
          ),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: disabled ? textGrey : textColor,
              ),
              if (label.isNotEmpty) const SizedBox(width: 6),
            ],
            if (label.isNotEmpty)
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: disabled ? textGrey : textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }

  Widget pageHeader() {
    final room = cleanRoom(widget.room);
    final roomText = room.isEmpty ? '-' : '$room호';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 18, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF16305E),
            Color(0xFF22437C),
          ],
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
              safeButton(
                label: '',
                icon: Icons.arrow_back_rounded,
                backgroundColor: Colors.white.withOpacity(0.18),
                textColor: Colors.white,
                borderColor: Colors.white.withOpacity(0.18),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'NRCAREC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              safeButton(
                label: '',
                icon: Icons.logout_rounded,
                backgroundColor: Colors.white.withOpacity(0.18),
                textColor: Colors.white,
                borderColor: Colors.white.withOpacity(0.18),
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();

                  if (!context.mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$roomText ${widget.patientName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '배설량을 기록해주세요',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            displayDateString,
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: mintSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: mintDark, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: textGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget statusChip(String label, bool recorded) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: recorded ? mintSoft : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: recorded ? const Color(0xFFC3D5EE) : const Color(0xFFFECACA),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recorded
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              size: 16,
              color: recorded ? mintDark : dangerColor,
            ),
            const SizedBox(width: 4),
            Text(
              '$label ${recorded ? "완료" : "미기록"}',
              maxLines: 1,
              style: TextStyle(
                color: recorded ? mintDark : dangerColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget mealStatusRow(Map<String, dynamic> data) {
    return Row(
      children: [
        Expanded(
          child: statusChip('아침', data['breakfastRecorded'] == true),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: statusChip('점심', data['lunchRecorded'] == true),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: statusChip('저녁', data['dinnerRecorded'] == true),
        ),
      ],
    );
  }

  Widget metricBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 108,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderGrey),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget metricGrid(Map<String, dynamic> data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double boxWidth = width < 360 ? (width - 8) / 2 : (width - 8) / 2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            metricBox(
              width: boxWidth,
              label: '고형식',
              value: '${data['totalFoodGram']} g',
              icon: Icons.rice_bowl_rounded,
              color: warningColor,
            ),
            metricBox(
              width: boxWidth,
              label: '국',
              value: '${data['totalSoupMl']} ml',
              icon: Icons.soup_kitchen_rounded,
              color: mintDark,
            ),
            metricBox(
              width: boxWidth,
              label: '수분',
              value: '${data['totalWaterMl']} ml',
              icon: Icons.water_drop_rounded,
              color: blueColor,
            ),
            metricBox(
              width: boxWidth,
              label: '총수분',
              value: '${data['totalFluidInputMl']} ml',
              icon: Icons.local_drink_rounded,
              color: successColor,
            ),
          ],
        );
      },
    );
  }

  Widget mealSummaryCard() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey('meal_$refreshKey'),
      future: loadMealSummary(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return sectionCard(
            child: Text(
              '식사 요약 오류: ${snapshot.error}',
              style: const TextStyle(
                color: dangerColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return sectionCard(
            child: const Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '오늘 식사/수분 요약 불러오는 중...',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data!;

        return sectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(
                icon: Icons.restaurant_rounded,
                title: '오늘 식사/수분 요약',
                subtitle: '환자가 입력한 섭취 기록입니다.',
              ),
              const SizedBox(height: 14),
              mealStatusRow(data),
              const SizedBox(height: 16),
              metricGrid(data),
            ],
          ),
        );
      },
    );
  }

  Widget choicePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? mintSoft : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? mint : borderGrey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: selected ? mintDark : textGrey,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? mintDark : textDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget amountStepButton(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mintSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC3D5EE)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: mintDark,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget amountStepper(TextEditingController controller) {
    return Row(
      children: [
        amountStepButton('-10', () => adjustAmount(controller, -10)),
        const SizedBox(width: 8),
        amountStepButton('+10', () => adjustAmount(controller, 10)),
        const SizedBox(width: 8),
        amountStepButton('+50', () => adjustAmount(controller, 50)),
        const SizedBox(width: 8),
        amountStepButton('+100', () => adjustAmount(controller, 100)),
      ],
    );
  }

  Widget urineTypeSelector() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            icon: Icons.water_drop_outlined,
            title: '배뇨 기록',
            subtitle: '배뇨 종류와 배뇨량을 입력합니다.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              choicePill(
                label: '자연배뇨',
                selected: urineType == 'natural',
                icon: Icons.water_drop_rounded,
                onTap: () => setState(() => urineType = 'natural'),
              ),
              choicePill(
                label: '카테타',
                selected: urineType == 'catheter',
                icon: Icons.medical_services_rounded,
                onTap: () => setState(() => urineType = 'catheter'),
              ),
              choicePill(
                label: '실금',
                selected: urineType == 'incontinence',
                icon: Icons.child_friendly_rounded,
                onTap: () => setState(() => urineType = 'incontinence'),
              ),
              choicePill(
                label: '기저귀',
                selected: urineType == 'diaper',
                icon: Icons.baby_changing_station,
                onTap: () => setState(() => urineType = 'diaper'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: urineAmountController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: inputDecoration(
              urineType == 'diaper' ? '기저귀 무게(g)' : '배뇨량(ml)',
            ),
          ),
          const SizedBox(height: 10),
          amountStepper(urineAmountController),
        ],
      ),
    );
  }

  Widget stoolSelector() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            icon: Icons.health_and_safety_rounded,
            title: '배변 기록',
            subtitle: '배변 여부와 필요 시 배변량을 입력합니다.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              choicePill(
                label: '없음',
                selected: !hasStool,
                icon: Icons.close_rounded,
                onTap: () {
                  setState(() {
                    hasStool = false;
                    stoolAmountController.clear();
                  });
                },
              ),
              choicePill(
                label: '있음',
                selected: hasStool,
                icon: Icons.check_rounded,
                onTap: () => setState(() => hasStool = true),
              ),
            ],
          ),
          if (hasStool) ...[
            const SizedBox(height: 16),
            TextField(
              controller: stoolAmountController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: inputDecoration('배변량(g, 선택)'),
            ),
            const SizedBox(height: 10),
            amountStepper(stoolAmountController),
            const SizedBox(height: 8),
            Row(
              children: [
                amountStepButton(
                  '계란 1개(+50g)',
                  () => adjustAmount(stoolAmountController, 50),
                ),
                const SizedBox(width: 8),
                amountStepButton(
                  '계란 2개(+100g)',
                  () => adjustAmount(stoolAmountController, 100),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '※ 자연배변을 "계란 몇 개" 정도로 표현할 때 사용하세요. 계란 1개 = 50g으로 더해집니다.',
              style: TextStyle(
                color: textGrey,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          bssReference(),
        ],
      ),
    );
  }

  // 배변 척도(BSS) 참고표 — 대시보드와 동일 기준. 입력값이 아니라 간호사 참고용.
  Widget bssReference() {
    const List<List<String>> stoolScale = [
      ['Type 1', '딱딱한 알갱이 · 심한 변비'],
      ['Type 2', '울퉁불퉁한 소시지형 · 변비'],
      ['Type 3', '표면에 균열 있는 소시지형 · 정상'],
      ['Type 4', '매끈한 소시지형 · 정상(이상적)'],
      ['Type 5', '부드러운 덩어리 · 섬유질 부족 경향'],
      ['Type 6', '경계 불분명한 죽 형태 · 경증 설사'],
      ['Type 7', '물 같은 액체 · 설사'],
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading:
              const Icon(Icons.menu_book_rounded, color: Color(0xFF16305E)),
          title: const Text(
            '배변 척도(BSS) 참고표',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          subtitle: const Text(
            '브리스톨 대변 척도 1~7',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          children: stoolScale.map((row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16305E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      row[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        row[1],
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget memoCard() {
    return sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(
            icon: Icons.note_alt_outlined,
            title: '메모',
            subtitle: '특이사항이 있으면 입력합니다.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: memoController,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            decoration: inputDecoration('메모'),
          ),
        ],
      ),
    );
  }

  Widget saveButton() {
    return safeButton(
      label: isSaving ? '저장 중...' : '배설 기록 저장',
      icon: Icons.save_rounded,
      backgroundColor: mintDark,
      textColor: Colors.white,
      height: 56,
      expand: true,
      onTap: isSaving ? null : saveOutput,
    );
  }

  Widget todayOutputRecords() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey('output_$refreshKey'),
      stream: FirebaseFirestore.instance
          .collection('output_records')
          .where('patientId', isEqualTo: widget.patientId)
          .where('date', isEqualTo: todayString)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return sectionCard(
            child: Text(
              '배설 기록 오류: ${snapshot.error}',
              style: const TextStyle(
                color: dangerColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final records = snapshot.data!.docs.toList();

        records.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;

          // 간호일이 자정을 넘길 수 있으므로 HH:mm 문자열이 아니라
          // 실제 타임스탬프(createdAt) 기준으로 최신순 정렬한다.
          final aTs = aData['createdAt'];
          final bTs = bData['createdAt'];
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }

          final aTime = (aData['time'] ?? '').toString();
          final bTime = (bData['time'] ?? '').toString();

          return bTime.compareTo(aTime);
        });

        if (records.isEmpty) {
          return sectionCard(
            child: const Column(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: textGrey,
                  size: 42,
                ),
                SizedBox(height: 10),
                Text(
                  '오늘 배설 기록 없음',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '배설 기록을 저장하면 여기에 표시됩니다.',
                  style: TextStyle(
                    color: textGrey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }

        return sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionTitle(
                icon: Icons.list_alt_rounded,
                title: '오늘 배설 기록',
                subtitle: '잘못 입력한 기록은 삭제할 수 있습니다.',
              ),
              const SizedBox(height: 14),
              ...records.map((doc) {
                final data = doc.data() as Map<String, dynamic>;

                final timeText = (data['time'] ?? '').toString();
                final urineLabel =
                    (data['urineTypeLabel'] ??
                            data['urineMethodLabel'] ??
                            '')
                        .toString();
                final urineAmount = toInt(data['urineAmount']);
                final urineUnit = (data['urineUnit'] ?? 'ml').toString();
                final stoolYn = data['stoolYn'] == true;
                final stoolAmount = toInt(data['stoolAmount']);
                final memo = (data['memo'] ?? '').toString();

                final stoolText = stoolYn
                    ? '배변 있음${stoolAmount > 0 ? " · ${stoolAmount}g" : ""}'
                    : '배변 없음';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderGrey),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: mintSoft,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          getUrineTypeIcon(data['urineType'] ?? ''),
                          color: mintDark,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$urineLabel $urineAmount $urineUnit / $stoolText',
                              style: const TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              memo.isEmpty ? timeText : '$timeText · $memo',
                              style: const TextStyle(
                                color: textGrey,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      safeButton(
                        label: '삭제',
                        icon: Icons.delete_outline_rounded,
                        backgroundColor: Colors.white,
                        textColor: dangerColor,
                        borderColor: dangerColor,
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onTap: () => deleteOutputRecord(doc.id),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    urineAmountController.dispose();
    stoolAmountController.dispose();
    memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = contentMaxWidth(constraints.maxWidth);

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pageHeader(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            mealSummaryCard(),
                            const SizedBox(height: 14),
                            urineTypeSelector(),
                            const SizedBox(height: 14),
                            stoolSelector(),
                            const SizedBox(height: 14),
                            memoCard(),
                            const SizedBox(height: 16),
                            saveButton(),
                            const SizedBox(height: 16),
                            todayOutputRecords(),
                            const SizedBox(height: 28),
                          ],
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