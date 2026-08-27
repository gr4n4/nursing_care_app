import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/food_table.dart';
import '../utils/care_date.dart';

/// 환자 한 명의 하루치 기록을 한 화면에 모아 보는 페이지.
///
/// 대시보드는 "옮겨 적을 숫자"를 보는 곳이고, 여기는 "무슨 일이 있었나"를 보는 곳이다.
/// 위에서부터 밸런스 → 식사/배설 상세 → 특이사항 순으로, 간호사가 궁금해하는
/// 순서대로 쌓는다.
///
/// 입력(부종·배변타입 선택, 밸런스 주의 해제)은 대시보드 첫 화면에서 하고
/// 여기서는 결과만 보여준다. 확인하는 곳과 기록하는 곳을 섞지 않기 위함.
class PatientDayPage extends StatefulWidget {
  final String patientId;
  final String name;
  final String room;
  final int age;

  const PatientDayPage({
    super.key,
    required this.patientId,
    required this.name,
    required this.room,
    required this.age,
  });

  @override
  State<PatientDayPage> createState() => _PatientDayPageState();
}

class _PatientDayPageState extends State<PatientDayPage> {
  static const Color mintDark = Color(0xFF16305E);
  static const Color mintSoft = Color(0xFFDCE7F5);
  static const Color pageBg = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color borderGrey = Color(0xFFE5E7EB);
  static const Color dangerColor = Color(0xFFEF4444);
  static const Color blueColor = Color(0xFF2563EB);
  static const Color purpleColor = Color(0xFF7C3AED);

  // 대시보드와 같은 기준을 쓴다. 두 화면의 숫자가 어긋나면 신뢰를 잃는다.
  static const List<List<String>> edemaScale = [
    ['0', '없음', '함몰 없음'],
    ['1', '+1', '2mm 함몰 · 즉시 회복'],
    ['2', '+2', '4mm 함몰 · 수 초 내 회복'],
    ['3', '+3', '6mm 함몰 · 10~30초 지속'],
    ['4', '+4', '8mm 함몰 · 30초 이상 지속'],
  ];

  static const List<List<String>> stoolScale = [
    ['0', '미선택', '아직 선택 안 함'],
    ['1', 'Type 1', '딱딱한 알갱이 · 심한 변비'],
    ['2', 'Type 2', '울퉁불퉁한 소시지형 · 변비'],
    ['3', 'Type 3', '표면에 균열 있는 소시지형 · 정상'],
    ['4', 'Type 4', '매끈한 소시지형 · 정상(이상적)'],
    ['5', 'Type 5', '부드러운 덩어리 · 섬유질 부족 경향'],
    ['6', 'Type 6', '경계 불분명한 죽 형태 · 경증 설사'],
    ['7', 'Type 7', '물 같은 액체 · 설사'],
  ];

  bool loading = true;
  String? loadError;

  List<Map<String, dynamic>> meals = [];
  Map<String, List<Map<String, dynamic>>> waterByCat = {};
  List<Map<String, dynamic>> outputs = [];
  Map<String, dynamic>? assess;

  int intakeMl = 0;
  int outputMl = 0;

  String get dateKey => careDateKey(DateTime.now());
  String get dateText => careDateDisplay(DateTime.now());
  String get weekdayText => careWeekday(DateTime.now());

  @override
  void initState() {
    super.initState();
    load();
  }

  int toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final results = await Future.wait([
        db
            .collection('meal_records')
            .where('patientId', isEqualTo: widget.patientId)
            .where('date', isEqualTo: dateKey)
            .get(),
        db
            .collection('water_records')
            .where('patientId', isEqualTo: widget.patientId)
            .where('date', isEqualTo: dateKey)
            .get(),
        db
            .collection('output_records')
            .where('patientId', isEqualTo: widget.patientId)
            .where('date', isEqualTo: dateKey)
            .get(),
      ]).timeout(const Duration(seconds: 30));

      final assessDoc = await db
          .collection('daily_assessments')
          .doc('${widget.patientId}_$dateKey')
          .get();

      if (!mounted) return;

      const mealOrder = {'breakfast': 0, 'lunch': 1, 'dinner': 2};
      final mealList = results[0].docs.map((d) => d.data()).toList()
        ..sort((a, b) => (mealOrder[a['mealType']] ?? 9)
            .compareTo(mealOrder[b['mealType']] ?? 9));

      final byCat = <String, List<Map<String, dynamic>>>{};
      for (final d in results[1].docs) {
        final data = d.data();
        byCat.putIfAbsent((data['category'] ?? 'drink').toString(), () => [])
            .add(data);
      }

      final outputList = results[2].docs.map((d) => d.data()).toList()
        ..sort((a, b) => (a['time'] ?? '').toString().compareTo(
              (b['time'] ?? '').toString(),
            ));

      // 섭취 = 식사에 든 수분 + 모든 water_records(음료·과일·관급식·수액)
      var intake = 0;
      for (final m in mealList) {
        intake += toInt(m['totalFluidMl']);
      }
      for (final list in byCat.values) {
        for (final w in list) {
          intake += toInt(w['amountMl']);
        }
      }

      // 배설 = 소변(ml) + 기저귀(g, 1g≈1ml)
      var out = 0;
      for (final o in outputList) {
        out += toInt(o['urineAmount']);
      }

      setState(() {
        meals = mealList;
        waterByCat = byCat;
        outputs = outputList;
        assess = assessDoc.data();
        intakeMl = intake;
        outputMl = out;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = '기록을 불러오지 못했습니다: $e';
        loading = false;
      });
    }
  }

  // ---------- 텍스트 ----------

  String mealLabelKo(String t) {
    if (t == 'breakfast') return '아침';
    if (t == 'lunch') return '점심';
    if (t == 'dinner') return '저녁';
    return t;
  }

  String catLabelKo(String c) {
    switch (c) {
      case 'drink':
        return '음료';
      case 'fruit':
        return '과일';
      case 'tube':
        return '관급식';
      case 'iv':
        return '수액';
      default:
        return c;
    }
  }

  String urineLabelKo(String t) {
    switch (t) {
      case 'catheter':
        return '카테타';
      case 'incontinence':
        return '실금';
      case 'diaper':
        return '기저귀';
      default:
        return '자연배뇨';
    }
  }

  String mealItemsText(Map<String, dynamic> m) {
    final parts = <String>[];

    void addItem(String type, dynamic ratio) {
      final t = type.trim();
      if (t.isEmpty || t == '없음' || t == '-') return;
      final r = (ratio ?? '').toString().trim();
      parts.add(r.isEmpty ? t : '$t $r');
    }

    addItem((m['stapleType'] ?? '주식').toString(), m['stapleRatio']);

    final soupRatio = (m['soupRatio'] ?? '').toString().trim();
    if (soupRatio.isNotEmpty &&
        soupRatio != '없음' &&
        toInt(m['soupServingGram']) > 0) {
      parts.add('국 $soupRatio');
    }
    for (var i = 1; i <= 4; i++) {
      addItem((m['side${i}Type'] ?? '').toString(), m['side${i}Ratio']);
    }

    return parts.isEmpty ? '기록됨' : parts.join(', ');
  }

  // ---------- 공통 UI ----------

  Widget card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderGrey),
      ),
      child: child,
    );
  }

  Widget cardTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: textDark,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget emptyLine() {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(
        '기록 없음',
        style: TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ---------- 카드들 ----------

  /// 상단 밸런스 카드. 이 화면에서 가장 먼저 보여야 할 숫자.
  Widget balanceCard() {
    final balance = intakeMl - outputMl;
    final over = balance.abs() > ioBalanceThresholdMl;
    final cleared = assess?['balanceCleared'] == true;
    final sign = balance > 0 ? '+' : '';

    Widget block(String label, String value, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Text(
              'ml',
              style: TextStyle(
                color: textGrey,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Widget symbol(String s) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            s,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

    // 주의 상태여도 간호사가 사유를 남겨 해제했으면 붉은 강조를 걷는다.
    final showWarning = over && !cleared;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: showWarning ? const Color(0xFFFEF2F2) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: showWarning ? const Color(0xFFFECACA) : borderGrey,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              block('섭취', '$intakeMl', mintDark),
              symbol('−'),
              block('배설', '$outputMl', blueColor),
              symbol('='),
              block(
                '밸런스',
                '$sign$balance',
                showWarning ? dangerColor : textDark,
              ),
            ],
          ),
          if (showWarning) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: dangerColor, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '±$ioBalanceThresholdMl ml를 넘었습니다. 대시보드에서 확인 처리할 수 있습니다.',
                    style: const TextStyle(
                      color: dangerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (over && cleared) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: mintDark, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '주의가 확인 처리된 상태입니다.',
                    style: TextStyle(
                      color: mintDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget mealCard() {
    final hasWater = waterByCat.isNotEmpty;

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardTitle('식사 · 섭취', Icons.restaurant_rounded, mintDark),
          if (meals.isEmpty && !hasWater) emptyLine(),
          for (final m in meals)
            line(
              mealLabelKo(m['mealType'].toString()),
              '${mealItemsText(m)}\n${toInt(m['totalFoodGram'])}g · 수분 ${toInt(m['totalFluidMl'])}ml',
            ),
          // 음료·과일·관급식·수액은 종류별로 묶어 보여준다.
          for (final cat in const ['drink', 'fruit', 'tube', 'iv'])
            if (waterByCat[cat] != null)
              for (final w in waterByCat[cat]!)
                line(
                  catLabelKo(cat),
                  '${w['name']} ${toInt(w['amountMl'])}ml'
                  '${(w['time'] ?? '').toString().isEmpty ? '' : '  (${w['time']})'}',
                ),
        ],
      ),
    );
  }

  Widget outputCard() {
    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardTitle('배설', Icons.water_drop_rounded, blueColor),
          if (outputs.isEmpty) emptyLine(),
          for (final o in outputs)
            line(
              urineLabelKo((o['urineType'] ?? 'natural').toString()),
              _outputText(o),
            ),
        ],
      ),
    );
  }

  String _outputText(Map<String, dynamic> o) {
    final amount = toInt(o['urineAmount']);
    final unit = (o['urineUnit'] ?? 'ml').toString();
    final time = (o['time'] ?? '').toString();

    final parts = <String>[];
    if (amount > 0) parts.add('$amount$unit');
    if (o['stoolYn'] == true) {
      final sg = toInt(o['stoolAmount']);
      parts.add('배변${sg > 0 ? ' ${sg}g' : ''}');
    }
    final body = parts.isEmpty ? '기록됨' : parts.join(' · ');
    return time.isEmpty ? body : '$body  ($time)';
  }

  /// 특이사항 — 부종·배변타입의 '기록된 값'과 그 단계 설명.
  /// 입력은 대시보드에서 하므로 여기서는 읽기 전용이다.
  Widget assessmentCard() {
    final edema = toInt(assess?['edemaGrade']);
    final stool = toInt(assess?['stoolType']);
    final cleared = assess?['balanceCleared'] == true;
    final reason = (assess?['balanceReason'] ?? '').toString();

    Widget scaleRow(String title, int value, List<List<String>> scale,
        Color color, String emptyText) {
      final valid = value > 0 && value < scale.length;
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (!valid)
              Text(
                emptyText,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      scale[value][1],
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 단계 설명을 함께 보여줘야 이 값이 무슨 뜻인지 알 수 있다.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        scale[value][2],
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardTitle('특이사항', Icons.assignment_rounded, purpleColor),
          scaleRow('부종 (Pitting Edema)', edema, edemaScale, purpleColor,
              '아직 기록되지 않음'),
          scaleRow('배변 타입 (Bristol Stool Scale)', stool, stoolScale, mintDark,
              '아직 기록되지 않음'),
          if (cleared) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mintSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC3D5EE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '밸런스 주의 해제됨',
                    style: TextStyle(
                      color: mintDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reason.isEmpty ? '사유 없음' : reason,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '부종·배변타입 입력과 주의 해제는 대시보드 첫 화면에서 합니다.',
            style: TextStyle(
              color: textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget pageHeader() {
    final room = widget.room.replaceAll('호', '').trim();

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
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: loading ? null : load,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0x2EFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 이름이 길어도 낱말 중간이 잘리지 않게 어절 단위로 흘린다.
          Wrap(
            spacing: 10,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              if (room.isNotEmpty)
                Text(
                  '$room호',
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              Text(
                widget.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (widget.age > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${widget.age}세',
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$dateText ($weekdayText) · 하루 기준 오전 7시',
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 13,
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
            // 넓으면 식사/배설을 좌우로, 좁으면 위아래로 쌓는다.
            final wide = constraints.maxWidth >= 860;
            final maxWidth = wide ? 1000.0 : constraints.maxWidth;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pageHeader(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        child: loading
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 60),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              )
                            : loadError != null
                                ? card(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '불러오기 실패',
                                          style: TextStyle(
                                            color: dangerColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SelectableText(
                                          loadError!,
                                          style: const TextStyle(
                                            color: dangerColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      balanceCard(),
                                      const SizedBox(height: 14),
                                      if (wide)
                                        IntrinsicHeight(
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(child: mealCard()),
                                              const SizedBox(width: 14),
                                              Expanded(child: outputCard()),
                                            ],
                                          ),
                                        )
                                      else ...[
                                        mealCard(),
                                        const SizedBox(height: 14),
                                        outputCard(),
                                      ],
                                      const SizedBox(height: 14),
                                      assessmentCard(),
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
