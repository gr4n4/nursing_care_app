import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/food_table.dart';
import '../utils/care_date.dart';
import '../utils/feedback.dart';
import 'patient_profile_edit_page.dart';

/// 섭취 입력 화면에서 보여줄 섹션.
/// null이면 4개 전부(기존 동작), 지정하면 그 섹션만 보여줘 스크롤을 줄인다.
///  meal   = 경구식(구강섭취 · 관급식) · tubeIv = 비경구식(수액 IV)
///  drink  = 수분섭취(음료 포함)   · fruit  = 기타섭취(과일)
enum IntakeSection { meal, tubeIv, drink, fruit }

/// 간호사가 특정 환자의 식사량 · 수분 · 기타 섭취(과일)를 기록하는 화면.
/// section 을 주면 해당 항목 하나만, 주지 않으면 접이식 카드 4개 전부를 보여준다.
class IntakeRecordPage extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String room;
  final IntakeSection? section;

  const IntakeRecordPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.room,
    this.section,
  });

  @override
  State<IntakeRecordPage> createState() => _IntakeRecordPageState();
}

class _IntakeRecordPageState extends State<IntakeRecordPage> {
  static const Color mint = Color(0xFF16305E);
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color blueColor = Color(0xFF2563EB);

  late String selectedPatientId;
  late String patientName;
  late String patientRoom;

  bool showMeal = true;
  bool showWater = false;
  bool showFruit = false;
  bool showTube = false;

  /// 경구식 카드 안의 [구강섭취 | 관급식] 세그먼트 선택 상태.
  /// 기본은 구강섭취(기존 동작) — 관급식은 탭 한 번으로 전환한다.
  bool tubeFeedMode = false;

  String? openMealType;
  bool isLoadingMeal = false;

  // 식사 입력 값 (제공량은 g 단위, 품목 기본값에서 시작해 연필로 수정 가능)
  String stapleType = '밥';
  double stapleRatio = 0;
  int stapleServing = 230;

  double soupRatio = 0;
  int soupServing = 200;

  String side1Type = '없음';
  String side2Type = '없음';
  String side3Type = '없음';
  String side4Type = '없음';

  double side1Ratio = 0;
  double side2Ratio = 0;
  double side3Ratio = 0;
  double side4Ratio = 0;

  int side1Serving = 0;
  int side2Serving = 0;
  int side3Serving = 0;
  int side4Serving = 0;

  final TextEditingController waterController = TextEditingController();
  final TextEditingController ivController = TextEditingController();
  final TextEditingController tubeController = TextEditingController();

  /// 본문 스크롤 컨트롤러.
  /// Scrollbar 는 컨트롤러 없이는 웹에서 PrimaryScrollController 를 못 찾아
  /// 'no ScrollPosition attached' assert 로 본문 페인트가 통째로 죽는다.
  /// (예전 station_page 블랭크 사고와 같은 원인 — 반드시 명시적으로 넘긴다.)
  final ScrollController pageController = ScrollController();

  /// 떠 있는 저장 바를 보여줄지. 맨 아래까지 내려오면 false 가 되고,
  /// 본문 끝에 있는 진짜 저장 버튼이 같은 자리에 그대로 드러난다.
  final ValueNotifier<bool> showFloatingSave = ValueNotifier<bool>(false);

  // 수분/과일: 품목별 섭취비율 + 제공량 override
  final Map<String, double> drinkRatios = {};
  final Map<String, int> drinkServing = {};
  final Map<String, double> fruitRatios = {};
  final Map<String, int> fruitServing = {};

  /// 카테고리 화면에서 한 항목만 골라 들어온 모드.
  /// 이때는 카드가 하나뿐이라 접기/펼치기가 의미 없다 → 처음부터 펼쳐 두고,
  /// 저장 후에도 접지 않는다(접으면 화면이 빈 카드 하나만 남는다).
  bool get isSingleSection => widget.section != null;

  @override
  void initState() {
    super.initState();
    selectedPatientId = widget.patientId;
    patientName = widget.patientName;
    patientRoom = widget.room;

    pageController.addListener(updateFloatingSave);

    final s = widget.section;
    if (s != null) {
      showMeal = s == IntakeSection.meal;
      showWater = s == IntakeSection.drink;
      showFruit = s == IntakeSection.fruit;
      showTube = s == IntakeSection.tubeIv;
    }

    for (final f in drinkFoods) {
      drinkServing[f.name] = f.servingGram;
      drinkRatios[f.name] = 0;
    }
    for (final f in fruitFoods) {
      fruitServing[f.name] = f.servingGram;
      fruitRatios[f.name] = 0;
    }
  }

  @override
  void dispose() {
    waterController.dispose();
    ivController.dispose();
    tubeController.dispose();
    pageController.dispose();
    showFloatingSave.dispose();
    super.dispose();
  }

  String get todayString => careDateKey(DateTime.now());
  String get displayDateString => careDateDisplay(DateTime.now());
  String get nowTimeString => wallClockTime(DateTime.now());

  double toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// 제공량(g)과 섭취비율로 실제 섭취 g.
  int gramOf(int serving, double ratio) => (serving * ratio).round();

  /// 제공량을 바꾸면 수분도 비율대로 환산한다.
  /// 수분 = 기본수분 × (수정제공량 / 기본제공량) × 섭취비율
  int waterOf(FoodItem food, int serving, double ratio) {
    if (food.servingGram <= 0) return 0;
    return (food.waterMl * serving / food.servingGram * ratio).round();
  }

  Future<void> reloadPatientInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('patients')
        .doc(selectedPatientId)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() {
        patientName = (data['name'] ?? '').toString();
        patientRoom = (data['room'] ?? '').toString();
      });
    }
  }

  int defaultStapleServing(String type) =>
      findFood(stapleFoods, type)?.servingGram ?? 230;
  int defaultSideServing(String type) =>
      findFood(sideFoods, type)?.servingGram ?? 0;

  void resetMealInputs() {
    stapleType = '밥';
    stapleRatio = 0;
    stapleServing = defaultStapleServing('밥');

    soupRatio = 0;
    soupServing = 200;

    side1Type = '없음';
    side2Type = '없음';
    side3Type = '없음';
    side4Type = '없음';

    side1Ratio = 0;
    side2Ratio = 0;
    side3Ratio = 0;
    side4Ratio = 0;

    side1Serving = 0;
    side2Serving = 0;
    side3Serving = 0;
    side4Serving = 0;
  }

  Future<void> openMeal(String mealType) async {
    setState(() {
      openMealType = mealType;
      isLoadingMeal = true;
      resetMealInputs();
    });

    try {
      final docId = '${selectedPatientId}_${todayString}_$mealType';
      final doc = await FirebaseFirestore.instance
          .collection('meal_records')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          stapleType = data['stapleType'] ?? data['riceType'] ?? '밥';
          stapleRatio = toDouble(data['stapleRatio'] ?? data['riceRatio']);
          stapleServing = data['stapleServingGram'] != null
              ? toInt(data['stapleServingGram'])
              : defaultStapleServing(stapleType);

          soupRatio = toDouble(data['soupRatio']);
          soupServing = data['soupServingGram'] != null
              ? toInt(data['soupServingGram'])
              : 200;

          side1Type = data['side1Type'] ?? '없음';
          side2Type = data['side2Type'] ?? '없음';
          side3Type = data['side3Type'] ?? '없음';
          side4Type = data['side4Type'] ?? '없음';

          side1Ratio = toDouble(data['side1Ratio']);
          side2Ratio = toDouble(data['side2Ratio']);
          side3Ratio = toDouble(data['side3Ratio']);
          side4Ratio = toDouble(data['side4Ratio']);

          side1Serving = data['side1ServingGram'] != null
              ? toInt(data['side1ServingGram'])
              : defaultSideServing(side1Type);
          side2Serving = data['side2ServingGram'] != null
              ? toInt(data['side2ServingGram'])
              : defaultSideServing(side2Type);
          side3Serving = data['side3ServingGram'] != null
              ? toInt(data['side3ServingGram'])
              : defaultSideServing(side3Type);
          side4Serving = data['side4ServingGram'] != null
              ? toInt(data['side4ServingGram'])
              : defaultSideServing(side4Type);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('식사 기록 불러오기 오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoadingMeal = false);
    }
  }

  Future<bool> confirmOverwrite(String mealType) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${mealLabel(mealType)} 식사량 변경'),
        content: Text(
          '${mealLabel(mealType)} 식사량이 이미 기록되어 있어요.\n정말 바꾸시겠어요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: mintDark,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> saveMeal(String mealType) async {
    final docId = '${selectedPatientId}_${todayString}_$mealType';
    final docRef =
        FirebaseFirestore.instance.collection('meal_records').doc(docId);

    final existing = await docRef.get();
    if (existing.exists) {
      final ok = await confirmOverwrite(mealType);
      if (!ok) return;
    }

    final staple = findFood(stapleFoods, stapleType) ?? stapleFoods.first;
    final stapleGram = gramOf(stapleServing, stapleRatio);
    final stapleWaterMl = waterOf(staple, stapleServing, stapleRatio);

    final soupWaterMl = waterOf(soupFood, soupServing, soupRatio);

    int sideGramOf(String type, int serving, double ratio) {
      if (findFood(sideFoods, type) == null) return 0;
      return gramOf(serving, ratio);
    }

    int sideWaterOf(String type, int serving, double ratio) {
      final f = findFood(sideFoods, type);
      if (f == null) return 0;
      return waterOf(f, serving, ratio);
    }

    final side1Gram = sideGramOf(side1Type, side1Serving, side1Ratio);
    final side2Gram = sideGramOf(side2Type, side2Serving, side2Ratio);
    final side3Gram = sideGramOf(side3Type, side3Serving, side3Ratio);
    final side4Gram = sideGramOf(side4Type, side4Serving, side4Ratio);

    final side1WaterMl = sideWaterOf(side1Type, side1Serving, side1Ratio);
    final side2WaterMl = sideWaterOf(side2Type, side2Serving, side2Ratio);
    final side3WaterMl = sideWaterOf(side3Type, side3Serving, side3Ratio);
    final side4WaterMl = sideWaterOf(side4Type, side4Serving, side4Ratio);

    final totalFoodGram =
        stapleGram + side1Gram + side2Gram + side3Gram + side4Gram;

    final totalFoodWaterMl = stapleWaterMl +
        soupWaterMl +
        side1WaterMl +
        side2WaterMl +
        side3WaterMl +
        side4WaterMl;

    final totalFluidMl = totalFoodWaterMl;

    await docRef.set({
      'patientId': selectedPatientId,
      'patientName': patientName,
      'room': patientRoom,
      'date': todayString,
      'time': nowTimeString,
      'mealType': mealType,
      'stapleType': stapleType,
      'stapleRatio': stapleRatio,
      'stapleServingGram': stapleServing,
      'stapleGram': stapleGram,
      'stapleWaterMl': stapleWaterMl,
      'soupRatio': soupRatio,
      'soupServingGram': soupServing,
      'soupWaterMl': soupWaterMl,
      'side1Type': side1Type,
      'side1Ratio': side1Ratio,
      'side1ServingGram': side1Serving,
      'side1Gram': side1Gram,
      'side1WaterMl': side1WaterMl,
      'side2Type': side2Type,
      'side2Ratio': side2Ratio,
      'side2ServingGram': side2Serving,
      'side2Gram': side2Gram,
      'side2WaterMl': side2WaterMl,
      'side3Type': side3Type,
      'side3Ratio': side3Ratio,
      'side3ServingGram': side3Serving,
      'side3Gram': side3Gram,
      'side3WaterMl': side3WaterMl,
      'side4Type': side4Type,
      'side4Ratio': side4Ratio,
      'side4ServingGram': side4Serving,
      'side4Gram': side4Gram,
      'side4WaterMl': side4WaterMl,
      'totalFoodGram': totalFoodGram,
      'totalFoodWaterMl': totalFoodWaterMl,
      'totalFluidMl': totalFluidMl,
      'updatedAt': Timestamp.now(),
    });

    if (!mounted) return;
    setState(() => openMealType = null);
    showSaveSuccess(context, message: '${mealLabel(mealType)} 식사가 기록되었습니다.');
  }

  Map<String, dynamic> waterRecordBase(String name, int amountMl, String cat) {
    return {
      'patientId': selectedPatientId,
      'patientName': patientName,
      'room': patientRoom,
      'date': todayString,
      'time': nowTimeString,
      'name': name,
      'category': cat,
      'amountMl': amountMl,
      'createdAt': Timestamp.now(),
    };
  }

  Future<void> saveDrinks() async {
    final col = FirebaseFirestore.instance.collection('water_records');
    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final f in drinkFoods) {
      final ratio = drinkRatios[f.name] ?? 0;
      if (ratio <= 0) continue;
      final ml = waterOf(f, drinkServing[f.name] ?? f.servingGram, ratio);
      if (ml <= 0) continue;
      batch.set(col.doc(), waterRecordBase(f.name, ml, 'drink'));
      count++;
    }

    final direct = int.tryParse(waterController.text.trim()) ?? 0;
    if (direct > 0) {
      batch.set(col.doc(), waterRecordBase('직접 입력', direct, 'drink'));
      count++;
    }

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 수분 항목이 없어요.')),
      );
      return;
    }

    await batch.commit();
    if (!mounted) return;

    setState(() {
      for (final f in drinkFoods) {
        drinkRatios[f.name] = 0;
      }
      waterController.clear();
      if (!isSingleSection) showWater = false;
    });
    showSaveSuccess(context, message: '수분 $count건이 기록되었습니다.');
  }

  Future<void> saveFruits() async {
    final col = FirebaseFirestore.instance.collection('water_records');
    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (final f in fruitFoods) {
      final ratio = fruitRatios[f.name] ?? 0;
      if (ratio <= 0) continue;
      final ml = waterOf(f, fruitServing[f.name] ?? f.servingGram, ratio);
      if (ml <= 0) continue;
      batch.set(col.doc(), waterRecordBase(f.name, ml, 'fruit'));
      count++;
    }

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 과일 항목이 없어요.')),
      );
      return;
    }

    await batch.commit();
    if (!mounted) return;

    setState(() {
      for (final f in fruitFoods) {
        fruitRatios[f.name] = 0;
      }
      if (!isSingleSection) showFruit = false;
    });
    showSaveSuccess(context, message: '기타 섭취 $count건이 기록되었습니다.');
  }

  Future<void> saveTubeIv() async {
    final iv = int.tryParse(ivController.text.trim()) ?? 0;

    if (iv <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수액 양을 입력해주세요.')),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('water_records')
        .add(waterRecordBase('수액', iv, 'iv'));
    if (!mounted) return;

    setState(() {
      ivController.clear();
      if (!isSingleSection) showTube = false;
    });
    showSaveSuccess(context, message: '수액 기록이 저장되었습니다.');
  }

  /// 관급식(경관영양) 주입량 저장.
  /// 수액과 같은 ml 모델이라 water_records 에 category 'tube' 로 넣는다.
  /// (대시보드 station_page 는 이미 'tube' 를 '관급식'으로 표시한다.)
  Future<void> saveTubeFeed() async {
    final ml = int.tryParse(tubeController.text.trim()) ?? 0;

    if (ml <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관급식 주입량을 입력해주세요.')),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('water_records')
        .add(waterRecordBase('관급식', ml, 'tube'));
    if (!mounted) return;

    setState(() => tubeController.clear());
    showSaveSuccess(context, message: '관급식 기록이 저장되었습니다.');
  }

  Future<void> deleteWaterRecord(String docId) async {
    await FirebaseFirestore.instance
        .collection('water_records')
        .doc(docId)
        .delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기록 삭제 완료')),
    );
  }

  double contentMaxWidth(double screenWidth) {
    if (screenWidth >= 900) return 520;
    return screenWidth;
  }

  String mealLabel(String mealType) {
    if (mealType == 'breakfast') return '아침';
    if (mealType == 'lunch') return '점심';
    if (mealType == 'dinner') return '저녁';
    return mealType;
  }

  IconData mealIcon(String mealType) {
    if (mealType == 'breakfast') return Icons.wb_sunny_rounded;
    if (mealType == 'lunch') return Icons.wb_twilight_rounded;
    if (mealType == 'dinner') return Icons.nightlight_round;
    return Icons.restaurant_rounded;
  }

  Color mealColor(String mealType) {
    if (mealType == 'breakfast') return const Color(0xFFF59E0B);
    if (mealType == 'lunch') return const Color(0xFFF97316);
    if (mealType == 'dinner') return const Color(0xFF818CF8);
    return mintDark;
  }

  ButtonStyle get primaryButtonStyle {
    return ElevatedButton.styleFrom(
      backgroundColor: mintDark,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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

  // 상단 민트 그라데이션 헤더 (배설량 페이지와 통일). 오른쪽 버튼은 정보수정.
  Widget pageHeader() {
    final cleanRoom = patientRoom.replaceAll('호', '').trim();
    final roomText = cleanRoom.isEmpty ? '' : '$cleanRoom호 ';

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
              headerIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'BALANCARE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              headerTextButton(
                label: '정보수정',
                icon: Icons.edit_rounded,
                onTap: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PatientProfileEditPage(
                        patientId: selectedPatientId,
                      ),
                    ),
                  );
                  if (updated == true) await reloadPatientInfo();
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$roomText$patientName'.trim().isEmpty
                ? '환자'
                : '$roomText$patientName',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '식사량을 기록해주세요',
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

  Widget headerIconButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget headerTextButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget accordionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailing,
    required Widget child,
  }) {
    // 단일 섹션 모드에서는 접을 일이 없으므로 화살표를 숨기고 탭도 막는다.
    final collapsible = !isSingleSection;
    return sectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: collapsible ? onToggle : null,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: mintSoft,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: mintDark, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
                if (collapsible) ...[
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: textGrey,
                    size: 28,
                  ),
                ],
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            child,
          ],
        ],
      ),
    );
  }

  // 제공량 수정 다이얼로그 → 새 값(int) 반환.
  // 컨트롤러 생명주기를 다이얼로그 위젯(_ServingEditDialog)이 직접 관리한다.
  // (메서드에서 만든 컨트롤러를 showDialog 후 수동 dispose하면 다이얼로그 닫힘
  //  애니메이션과 레이스가 나면서 모바일에서 '_dependents.isEmpty' assertion이 뜬다.)
  Future<int?> askServing(String label, int current) {
    return showDialog<int>(
      context: context,
      builder: (_) => _ServingEditDialog(label: label, current: current),
    );
  }

  Widget servingPill({required int serving, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: mintSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFC3D5EE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '제공량 ${serving}g',
              style: const TextStyle(
                color: mintDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_rounded, size: 13, color: mintDark),
          ],
        ),
      ),
    );
  }

  // ---------- 식사량 ----------

  Widget mealCard({
    required String mealType,
    required bool recorded,
    required int foodGram,
    required int fluidMl,
  }) {
    final isOpen = openMealType == mealType;
    final color = mealColor(mealType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isOpen ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpen ? mint : borderGrey,
          width: isOpen ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              if (isOpen) {
                setState(() => openMealType = null);
              } else {
                openMeal(mealType);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: recorded
                          ? color.withOpacity(0.15)
                          : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      mealIcon(mealType),
                      color: recorded ? color : const Color(0xFFCBD5E1),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mealLabel(mealType),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          recorded
                              ? '기록 완료 · 식사 ${foodGram}g · 수분 ${fluidMl}ml'
                              : '미기록',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: recorded ? mintDark : textGrey,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (recorded && !isOpen)
                    Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: mint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 18),
                    )
                  else
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: textGrey,
                      size: 24,
                    ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(13),
              child: mealForm(mealType),
            ),
          ],
        ],
      ),
    );
  }

  Widget mealForm(String mealType) {
    if (isLoadingMeal) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(color: mintDark)),
      );
    }

    return Column(
      children: [
        foodRow(
          title: '주식',
          unitText: '밥·진밥·된죽·죽·미음',
          ratio: stapleRatio,
          onRatioChanged: (v) => setState(() => stapleRatio = v),
          serving: stapleServing,
          onEditServing: () async {
            final v = await askServing('주식', stapleServing);
            if (v != null) setState(() => stapleServing = v);
          },
          extraSelector: stapleTypeSelector(),
        ),
        foodRow(
          title: '국',
          unitText: '국물 기준',
          ratio: soupRatio,
          onRatioChanged: (v) => setState(() => soupRatio = v),
          serving: soupServing,
          onEditServing: () async {
            final v = await askServing('국', soupServing);
            if (v != null) setState(() => soupServing = v);
          },
        ),
        sideRow(1),
        sideRow(2),
        sideRow(3),
        sideRow(4),
        // 단일 섹션 모드에서는 하단 고정 바(stickySaveBar)가 저장을 맡는다.
        if (!isSingleSection) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: primaryButtonStyle,
              onPressed: () => saveMeal(mealType),
              icon: const Icon(Icons.save_rounded),
              label: Text('${mealLabel(mealType)} 식사 기록 저장'),
            ),
          ),
        ],
      ],
    );
  }

  Widget sideRow(int index) {
    final type = [side1Type, side2Type, side3Type, side4Type][index - 1];
    final ratio = [side1Ratio, side2Ratio, side3Ratio, side4Ratio][index - 1];
    final serving =
        [side1Serving, side2Serving, side3Serving, side4Serving][index - 1];

    void setType(String v) {
      setState(() {
        final newServing = defaultSideServing(v);
        switch (index) {
          case 1:
            side1Type = v;
            side1Serving = newServing;
            if (v == '없음') side1Ratio = 0;
            break;
          case 2:
            side2Type = v;
            side2Serving = newServing;
            if (v == '없음') side2Ratio = 0;
            break;
          case 3:
            side3Type = v;
            side3Serving = newServing;
            if (v == '없음') side3Ratio = 0;
            break;
          case 4:
            side4Type = v;
            side4Serving = newServing;
            if (v == '없음') side4Ratio = 0;
            break;
        }
      });
    }

    void setRatio(double v) {
      setState(() {
        switch (index) {
          case 1:
            side1Ratio = v;
            break;
          case 2:
            side2Ratio = v;
            break;
          case 3:
            side3Ratio = v;
            break;
          case 4:
            side4Ratio = v;
            break;
        }
      });
    }

    void setServing(int v) {
      setState(() {
        switch (index) {
          case 1:
            side1Serving = v;
            break;
          case 2:
            side2Serving = v;
            break;
          case 3:
            side3Serving = v;
            break;
          case 4:
            side4Serving = v;
            break;
        }
      });
    }

    return foodRow(
      title: '반찬$index',
      unitText: '품목 선택',
      ratio: ratio,
      onRatioChanged: setRatio,
      serving: type == '없음' ? null : serving,
      onEditServing: type == '없음'
          ? null
          : () async {
              final v = await askServing('반찬$index', serving);
              if (v != null) setServing(v);
            },
      sideType: type,
      onSideTypeChanged: setType,
    );
  }

  Widget foodRow({
    required String title,
    required String unitText,
    required double ratio,
    required ValueChanged<double> onRatioChanged,
    int? serving,
    VoidCallback? onEditServing,
    String? sideType,
    ValueChanged<String>? onSideTypeChanged,
    Widget? extraSelector,
  }) {
    final isSideDish = sideType != null && onSideTypeChanged != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderGrey),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 20, color: mintDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title  ·  $unitText',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
              ),
              if (serving != null && onEditServing != null)
                servingPill(serving: serving, onTap: onEditServing),
            ],
          ),
          if (extraSelector != null) ...[
            const SizedBox(height: 10),
            extraSelector,
          ],
          if (isSideDish) ...[
            const SizedBox(height: 10),
            sideTypeSelector(value: sideType, onChanged: onSideTypeChanged),
          ],
          const SizedBox(height: 10),
          ratioSelector(value: ratio, onChanged: onRatioChanged),
        ],
      ),
    );
  }

  Widget smallChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      selectedColor: mintSoft,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? mint : borderGrey),
      labelStyle: TextStyle(
        color: selected ? mintDark : textDark,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (_) => onTap(),
    );
  }

  Widget ratioSelector({
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    Widget chip(String label, double v) => smallChip(
          label: label,
          selected: value == v,
          onTap: () => onChanged(v),
        );

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        chip('0', 0),
        chip('1/4', 0.25),
        chip('1/3', 0.33),
        chip('1/2', 0.5),
        chip('전체', 1.0),
      ],
    );
  }

  Widget stapleTypeSelector() {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: stapleFoods.map((food) {
        return smallChip(
          label: food.name,
          selected: stapleType == food.name,
          onTap: () => setState(() {
            stapleType = food.name;
            stapleServing = food.servingGram;
          }),
        );
      }).toList(),
    );
  }

  Widget sideTypeSelector({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children:
          ['없음', '고기', '생선', '계란', '두부', '포기김치', '물김치'].map((label) {
        return smallChip(
          label: label,
          selected: value == label,
          onTap: () => onChanged(label),
        );
      }).toList(),
    );
  }

  Widget mealSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('meal_records')
          .where('patientId', isEqualTo: selectedPatientId)
          .where('date', isEqualTo: todayString)
          .snapshots(),
      builder: (context, snapshot) {
        final Map<String, Map<String, dynamic>> mealMap = {};
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final mealType = (data['mealType'] ?? '').toString();
            if (mealType.isNotEmpty) mealMap[mealType] = data;
          }
        }

        Widget cardFor(String type) {
          final data = mealMap[type];
          return mealCard(
            mealType: type,
            recorded: data != null,
            foodGram: toInt(data?['totalFoodGram']),
            fluidMl: toInt(data?['totalFluidMl']),
          );
        }

        return Column(
          children: [
            cardFor('breakfast'),
            cardFor('lunch'),
            cardFor('dinner'),
          ],
        );
      },
    );
  }

  // ---------- 수분/과일 공용 인라인 품목 행 ----------

  Widget intakeRow({
    required FoodItem food,
    required double ratio,
    required int serving,
    required ValueChanged<double> onRatioChanged,
    required VoidCallback onEditServing,
  }) {
    final selected = ratio > 0;
    final ml = waterOf(food, serving, ratio);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: selected ? mintSoft : Colors.white,
        border: Border.all(color: selected ? mint : borderGrey),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  food.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '$ml ml',
                    style: const TextStyle(
                      color: blueColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              servingPill(serving: serving, onTap: onEditServing),
            ],
          ),
          const SizedBox(height: 10),
          ratioSelector(value: ratio, onChanged: onRatioChanged),
        ],
      ),
    );
  }

  Widget waterSection(int todayTotal, List<QueryDocumentSnapshot> records) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...drinkFoods.map((f) => intakeRow(
              food: f,
              ratio: drinkRatios[f.name] ?? 0,
              serving: drinkServing[f.name] ?? f.servingGram,
              onRatioChanged: (v) =>
                  setState(() => drinkRatios[f.name] = v),
              onEditServing: () async {
                final v = await askServing(
                    f.name, drinkServing[f.name] ?? f.servingGram);
                if (v != null) setState(() => drinkServing[f.name] = v);
              },
            )),
        const SizedBox(height: 4),
        TextField(
          controller: waterController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '직접 입력(ml)',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: borderGrey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: mintDark, width: 1.5),
            ),
          ),
        ),
        if (!isSingleSection) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: primaryButtonStyle,
              onPressed: saveDrinks,
              icon: const Icon(Icons.save_rounded),
              label: const Text('수분 기록 저장'),
            ),
          ),
        ],
        if (records.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('최근 수분 기록',
              style: TextStyle(
                  color: textDark, fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...records.take(4).map(recentRecordTile),
        ],
      ],
    );
  }

  Widget recentRecordTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final amount = toInt(data['amountMl']);
    final name = (data['name'] ?? '수분').toString();
    final timeText = (data['time'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGrey),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop_rounded, color: blueColor, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(timeText,
                style: const TextStyle(
                    color: textGrey, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Text('$amount ml',
                style: const TextStyle(
                    color: textDark, fontWeight: FontWeight.w900)),
          ),
          Text(name,
              style:
                  const TextStyle(color: textGrey, fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded),
            color: dangerColor,
            onPressed: () => deleteWaterRecord(doc.id),
          ),
        ],
      ),
    );
  }

  Widget waterCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('water_records')
          .where('patientId', isEqualTo: selectedPatientId)
          .where('date', isEqualTo: todayString)
          .snapshots(),
      builder: (context, snapshot) {
        int total = 0;
        final records = snapshot.data?.docs.toList() ?? [];
        records.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTs = aData['createdAt'];
          final bTs = bData['createdAt'];
          if (aTs is Timestamp && bTs is Timestamp) return bTs.compareTo(aTs);
          return (bData['time'] ?? '')
              .toString()
              .compareTo((aData['time'] ?? '').toString());
        });
        for (final doc in records) {
          total += toInt((doc.data() as Map<String, dynamic>)['amountMl']);
        }

        return accordionCard(
          icon: Icons.water_drop_outlined,
          title: '수분량',
          subtitle: '품목별 섭취 비율을 고르고 저장하세요.',
          expanded: showWater,
          onToggle: () => setState(() => showWater = !showWater),
          trailing: Text(
            '$total ml',
            style: const TextStyle(
              color: blueColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          child: waterSection(total, records),
        );
      },
    );
  }

  Widget fruitCard() {
    return accordionCard(
      icon: Icons.eco_rounded,
      title: '기타 섭취 (과일)',
      subtitle: '과일별 섭취 비율을 고르고 저장하세요.',
      expanded: showFruit,
      onToggle: () => setState(() => showFruit = !showFruit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...fruitFoods.map((f) => intakeRow(
                food: f,
                ratio: fruitRatios[f.name] ?? 0,
                serving: fruitServing[f.name] ?? f.servingGram,
                onRatioChanged: (v) =>
                    setState(() => fruitRatios[f.name] = v),
                onEditServing: () async {
                  final v = await askServing(
                      f.name, fruitServing[f.name] ?? f.servingGram);
                  if (v != null) setState(() => fruitServing[f.name] = v);
                },
              )),
          if (!isSingleSection) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: primaryButtonStyle,
                onPressed: saveFruits,
                icon: const Icon(Icons.save_rounded),
                label: const Text('기타 섭취 기록 저장'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget mlPresetEntry({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required Color color,
  }) {
    const presets = [50, 100, 200, 300, 400, 500];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: presets.map((ml) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  controller.text = ml.toString();
                  controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: controller.text.length),
                  );
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: mintSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFC3D5EE)),
                  ),
                  child: Text(
                    '$ml',
                    style: const TextStyle(
                      color: mintDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: hint,
              suffixText: 'ml',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: borderGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: mintDark, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 경구식 안의 [구강섭취 | 관급식] 전환 세그먼트.
  /// 카테고리 화면 카드를 늘리지 않고 이 한 줄(52px)만 추가해 스크롤을 유지한다.
  Widget oralModeSegment() {
    Widget seg(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? mintDark : textGrey),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: selected ? mintDark : textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: mintSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC3D5EE)),
      ),
      child: Row(
        children: [
          seg('구강섭취', Icons.restaurant_rounded, !tubeFeedMode,
              () => setState(() => tubeFeedMode = false)),
          seg('관급식', Icons.medical_services_rounded, tubeFeedMode,
              () => setState(() => tubeFeedMode = true)),
        ],
      ),
    );
  }

  /// 관급식 입력 본문 — 단위·프리셋은 수액과 동일(50~500ml + 직접 입력).
  Widget tubeFeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mlPresetEntry(
          label: '관급식 (경관영양)',
          hint: '주입량',
          controller: tubeController,
          icon: Icons.medical_services_rounded,
          color: mintDark,
        ),
        if (!isSingleSection) ...[
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: primaryButtonStyle,
              onPressed: saveTubeFeed,
              icon: const Icon(Icons.save_rounded),
              label: const Text('관급식 기록 저장'),
            ),
          ),
        ],
      ],
    );
  }

  Widget tubeIvCard() {
    return accordionCard(
      icon: Icons.water_drop_rounded,
      title: '비경구식',
      subtitle: '수액(IV)을 ml로 기록합니다.',
      expanded: showTube,
      onToggle: () => setState(() => showTube = !showTube),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mlPresetEntry(
            label: '수액 (비경구 · IV)',
            hint: '수액량',
            controller: ivController,
            icon: Icons.water_drop_rounded,
            color: blueColor,
          ),
          if (!isSingleSection) ...[
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: primaryButtonStyle,
                onPressed: saveTubeIv,
                icon: const Icon(Icons.save_rounded),
                label: const Text('수액 기록 저장'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 하단 고정 저장 바 ----------
  // 품목이 많은 화면(구강섭취·수분·기타섭취)에서 저장하려고 끝까지 스크롤하다
  // 다른 항목을 잘못 건드리는 사고를 막는다. 버튼은 항상 화면 아래에 붙어 있다.

  /// 지금 화면에서 저장할 대상. null 이면 아직 저장할 게 없다
  /// (구강섭취에서 아침/점심/저녁을 아직 안 고른 상태).
  ({VoidCallback onPressed, String label})? stickySaveAction() {
    switch (widget.section) {
      case IntakeSection.meal:
        if (tubeFeedMode) {
          return (onPressed: saveTubeFeed, label: '관급식 기록 저장');
        }
        final open = openMealType;
        if (open == null) return null;
        return (
          onPressed: () => saveMeal(open),
          label: '${mealLabel(open)} 식사 기록 저장',
        );
      case IntakeSection.drink:
        return (onPressed: saveDrinks, label: '수분 기록 저장');
      case IntakeSection.fruit:
        return (onPressed: saveFruits, label: '기타 섭취 기록 저장');
      case IntakeSection.tubeIv:
        return (onPressed: saveTubeIv, label: '수액 기록 저장');
      case null:
        return null;
    }
  }

  /// 품목을 고르는 화면(수분·기타섭취)에서만, 지금 몇 건 · 몇 ml가 저장되는지
  /// 버튼 위에 요약해 준다. 스크롤을 올리지 않아도 선택 상태를 확인할 수 있다.
  String? stickySummary() {
    if (widget.section == IntakeSection.drink) {
      int count = 0;
      int ml = 0;
      for (final f in drinkFoods) {
        final ratio = drinkRatios[f.name] ?? 0;
        if (ratio <= 0) continue;
        count++;
        ml += waterOf(f, drinkServing[f.name] ?? f.servingGram, ratio);
      }
      final direct = int.tryParse(waterController.text.trim()) ?? 0;
      if (direct > 0) {
        count++;
        ml += direct;
      }
      return count == 0 ? '선택된 항목 없음' : '$count건 · $ml ml';
    }

    if (widget.section == IntakeSection.fruit) {
      int count = 0;
      int ml = 0;
      for (final f in fruitFoods) {
        final ratio = fruitRatios[f.name] ?? 0;
        if (ratio <= 0) continue;
        count++;
        ml += waterOf(f, fruitServing[f.name] ?? f.servingGram, ratio);
      }
      return count == 0 ? '선택된 항목 없음' : '$count건 · $ml ml';
    }

    return null;
  }

  /// 하단에 도달했는지 확인해 떠 있는 바를 켜고 끈다.
  /// 스크롤할 때(리스너)와 매 프레임 이후(레이아웃 변화 반영) 둘 다에서 호출한다.
  void updateFloatingSave() {
    if (!pageController.hasClients) return;
    final pos = pageController.position;
    final scrollable = pos.maxScrollExtent > 8;
    final atBottom = pos.maxScrollExtent - pos.pixels <= 8;
    final next = scrollable && !atBottom;
    if (showFloatingSave.value != next) showFloatingSave.value = next;
  }

  /// 저장 버튼 블록. 본문 맨 끝과 떠 있는 바가 '같은 위젯'을 써야
  /// 아래로 다 내렸을 때 자리가 정확히 겹쳐 하나처럼 보인다.
  Widget saveBlock(({VoidCallback onPressed, String label}) action) {
    Widget summaryText() {
      final summary = stickySummary();
      if (summary == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          summary,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: textGrey,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    // 수분 화면의 '직접 입력' 칸은 setState를 타지 않으므로 컨트롤러를 직접 구독한다.
    final Widget summary = widget.section == IntakeSection.drink
        ? ValueListenableBuilder<TextEditingValue>(
            valueListenable: waterController,
            builder: (_, _, _) => summaryText(),
          )
        : summaryText();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        summary,
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: primaryButtonStyle,
            onPressed: action.onPressed,
            icon: const Icon(Icons.save_rounded),
            label: Text(action.label),
          ),
        ),
      ],
    );
  }

  /// 본문 위에 떠 있는 저장 바. 배경을 pageBg 로 맞춰서
  /// 사라질 때 색이 튀지 않고 본문 버튼과 자연스럽게 이어진다.
  Widget floatingSaveBar({
    required ({VoidCallback onPressed, String label}) action,
    required double maxContentWidth,
    required double safeBottom,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: pageBg,
        border: Border(top: BorderSide(color: borderGrey)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safeBottom),
            child: saveBlock(action),
          ),
        ),
      ),
    );
  }

  // section 이 지정되면 그 카드 하나만, null 이면 4개 전부를 14px 간격으로 쌓는다.
  List<Widget> sectionCards() {
    final s = widget.section;
    final cards = <Widget>[];

    if (s == null || s == IntakeSection.meal) {
      cards.add(
        accordionCard(
          icon: tubeFeedMode
              ? Icons.medical_services_rounded
              : Icons.restaurant_rounded,
          title: '경구식',
          subtitle: tubeFeedMode
              ? '관급식 주입량을 ml로 기록합니다.'
              : '아침·점심·저녁을 눌러 기록합니다.',
          expanded: showMeal,
          onToggle: () => setState(() => showMeal = !showMeal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              oralModeSegment(),
              const SizedBox(height: 14),
              if (tubeFeedMode) tubeFeedSection() else mealSection(),
            ],
          ),
        ),
      );
    }
    if (s == null || s == IntakeSection.drink) cards.add(waterCard());
    if (s == null || s == IntakeSection.fruit) cards.add(fruitCard());
    if (s == null || s == IntakeSection.tubeIv) cards.add(tubeIvCard());

    final spaced = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 14));
      spaced.add(cards[i]);
    }
    return spaced;
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final action = isSingleSection ? stickySaveAction() : null;

    // 카드가 펼쳐지거나 항목을 고르면 본문 높이가 바뀌므로 매 프레임 뒤에 다시 판정한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => updateFloatingSave());

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxContentWidth = contentMaxWidth(constraints.maxWidth);

            return Stack(
              children: [
                Scrollbar(
                  controller: pageController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: pageController,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pageHeader(),
                            Padding(
                              // 저장 버튼이 붙는 경우, 아래 여백을 떠 있는 바와
                              // 똑같이 맞춰야 끝까지 내렸을 때 자리가 겹친다.
                              padding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                action == null ? 28 : 12 + safeBottom,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...sectionCards(),
                                  if (action != null) ...[
                                    const SizedBox(height: 14),
                                    saveBlock(action),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (action != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: showFloatingSave,
                      builder: (_, show, _) => IgnorePointer(
                        // 숨겨진 동안에는 탭이 본문 버튼으로 그대로 통과한다.
                        ignoring: !show,
                        child: AnimatedOpacity(
                          opacity: show ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: floatingSaveBar(
                            action: action,
                            maxContentWidth: maxContentWidth,
                            safeBottom: safeBottom,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 제공량(g) 수정 다이얼로그. 컨트롤러를 위젯 생명주기에 맞춰 dispose하므로
/// 모바일에서 다이얼로그 닫힘 레이스로 인한 '_dependents.isEmpty' assertion이 발생하지 않는다.
class _ServingEditDialog extends StatefulWidget {
  final String label;
  final int current;

  const _ServingEditDialog({required this.label, required this.current});

  @override
  State<_ServingEditDialog> createState() => _ServingEditDialogState();
}

class _ServingEditDialogState extends State<_ServingEditDialog> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color textGrey = Color(0xFF64748B);

  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.current.toString());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('${widget.label} 제공량 수정'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1회 제공량(g)을 실제 기준에 맞게 수정하세요.\n수분량도 이 값에 비례해 자동 환산됩니다.',
            style: TextStyle(color: textGrey, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '제공량(g)',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: mintDark,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }

  void _submit() {
    final v = int.tryParse(controller.text.trim());
    Navigator.pop(context, (v == null || v < 0) ? null : v);
  }
}
