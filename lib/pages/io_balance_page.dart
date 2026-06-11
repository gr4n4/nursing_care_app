import 'package:flutter/material.dart';

class IoBalancePage extends StatefulWidget {
  const IoBalancePage({super.key});

  @override
  State<IoBalancePage> createState() => _IoBalancePageState();
}

class _IoBalancePageState extends State<IoBalancePage> {
  final amountController = TextEditingController(text: '150');
  final waterController = TextEditingController(text: '1200');
  final weightController = TextEditingController(text: '60');

  String selectedFood = '밥(쌀밥)';
  String selectedRatio = '전체';
  String selectedActivity = '보통';

  final List<IntakeFood> foods = [];

  final Map<String, double> foodWaterRatio = {
    '밥(쌀밥)': 0.60,
    '국/탕': 0.90,
    '김치': 0.88,
    '죽': 0.85,
    '과일': 0.85,
    '채소반찬': 0.80,
    '고기반찬': 0.55,
  };

  final Map<String, double> ratioMap = {
    '전체': 1.0,
    '1/2': 0.5,
    '1/3': 1 / 3,
    '1/4': 0.25,
    '거의 안 먹음': 0.05,
  };

  final Map<String, double> activityFactor = {
    '낮음': 0.9,
    '보통': 1.0,
    '높음': 1.15,
  };

  void addFood() {
    final providedAmount = double.tryParse(amountController.text) ?? 0;
    final ratio = ratioMap[selectedRatio] ?? 1.0;
    final eatenAmount = providedAmount * ratio;
    final waterRatio = foodWaterRatio[selectedFood] ?? 0.7;
    final foodWater = eatenAmount * waterRatio;

    setState(() {
      foods.add(
        IntakeFood(
          name: selectedFood,
          providedAmount: providedAmount,
          ratioLabel: selectedRatio,
          eatenAmount: eatenAmount,
          waterAmount: foodWater,
        ),
      );
    });
  }

  double get foodWaterTotal =>
      foods.fold(0, (sum, item) => sum + item.waterAmount);

  double get drinkWater => double.tryParse(waterController.text) ?? 0;

  double get weight => double.tryParse(weightController.text) ?? 0;

  double get metabolicWater => 300;

  double get insensibleLoss {
    final factor = activityFactor[selectedActivity] ?? 1.0;
    return weight * 13 * factor;
  }

  double get stoolWater => 150;

  double get expectedUrine {
    return foodWaterTotal + drinkWater + metabolicWater - insensibleLoss - stoolWater;
  }

  String get urineStatus {
    if (expectedUrine < 500) return '위험';
    if (expectedUrine < 1000) return '주의';
    if (expectedUrine <= 2000) return '정상';
    return '많음';
  }

  Color get statusColor {
    switch (urineStatus) {
      case '정상':
        return Colors.blue;
      case '주의':
        return Colors.orange;
      case '위험':
        return Colors.red;
      default:
        return Colors.purple;
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    waterController.dispose();
    weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalInput = foodWaterTotal + drinkWater + metabolicWater;

    return Scaffold(
      appBar: AppBar(
        title: const Text('섭취/배설량 계산'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionCard(
              title: '먹은 음식 추가',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          value: selectedFood,
                          items: foodWaterRatio.keys
                              .map((food) => DropdownMenuItem(
                                    value: food,
                                    child: Text(food),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedFood = value!);
                          },
                          decoration: const InputDecoration(labelText: '음식'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '제공량',
                            suffixText: 'g/ml',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedRatio,
                          items: ratioMap.keys
                              .map((ratio) => DropdownMenuItem(
                                    value: ratio,
                                    child: Text(ratio),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedRatio = value!);
                          },
                          decoration: const InputDecoration(labelText: '섭취비율'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: addFood,
                        child: const Text('+ 추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...foods.map(
                    (food) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${food.name} - 제공 ${food.providedAmount.toStringAsFixed(0)}g × ${food.ratioLabel} = 섭취 ${food.eatenAmount.toStringAsFixed(0)}g / 수분 ${food.waterAmount.toStringAsFixed(0)}mL',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => foods.remove(food));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _inputCard(
                    label: '음용수·음료 (mL)',
                    controller: waterController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _inputCard(
                    label: '체중 (kg)',
                    controller: weightController,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: '활동량',
              child: DropdownButtonFormField<String>(
                value: selectedActivity,
                items: activityFactor.keys
                    .map((activity) => DropdownMenuItem(
                          value: activity,
                          child: Text(activity),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => selectedActivity = value!);
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _resultCard(
                    title: '예상 소변량',
                    value: '${expectedUrine.clamp(0, 9999).toStringAsFixed(0)} mL/일',
                    subtitle: '상태: $urineStatus / 정상 1000~2000mL',
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _resultCard(
                    title: '예상 대변량',
                    value: '${stoolWater.toStringAsFixed(0)} mL/일',
                    subtitle: '기본 추정값',
                    color: Colors.brown,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '섭취: 음식수분 ${foodWaterTotal.toStringAsFixed(0)} + 음용수 ${drinkWater.toStringAsFixed(0)} + 대사수 ${metabolicWater.toStringAsFixed(0)} = ${totalInput.toStringAsFixed(0)}mL',
            ),
            Text(
              '배출 추정: 불감손실 ${insensibleLoss.toStringAsFixed(0)} + 대변수분 ${stoolWater.toStringAsFixed(0)} 차감',
            ),
            const SizedBox(height: 24),
            const Text(
              '계산 로직',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• 음식수분 = 실제섭취량 × 음식별 수분함량'),
            const Text('• 실제섭취량 = 제공량 × 섭취비율'),
            const Text('• 총 섭취수분 = 음식수분 + 음용수 + 대사수'),
            const Text('• 예상 소변량 = 총 섭취수분 - 불감손실 - 대변수분'),
            const Text('• 불감손실 = 체중 × 13mL/kg/일 × 활동계수'),
            const SizedBox(height: 16),
            Text(
              '※ 본 계산은 수분수지 추정 보조용입니다. 환자 상태, 발열, 설사, 구토, 발한, 신장기능, 수액 처방 등에 따라 실제 수분수지는 달라질 수 있습니다.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _inputCard({
    required String label,
    required TextEditingController controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _resultCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle),
        ],
      ),
    );
  }
}

class IntakeFood {
  final String name;
  final double providedAmount;
  final String ratioLabel;
  final double eatenAmount;
  final double waterAmount;

  IntakeFood({
    required this.name,
    required this.providedAmount,
    required this.ratioLabel,
    required this.eatenAmount,
    required this.waterAmount,
  });
}