/// 원내 환자식이 1회 제공량과 수분량 (국립농업과학원 발췌).
///
/// 각 품목은 1회 제공량(g)과 그 안의 수분함량(ml)을 가진다.
/// 실제 섭취량 = 제공량 × 섭취비율(0 / 1/4 / 1/3 / 1/2 / 전체),
/// 실제 수분섭취 = 수분함량 × 섭취비율.
class FoodItem {
  final String name;
  final int servingGram; // 1회 제공량 (g)
  final double waterMl; // 수분함량 (ml)

  const FoodItem(this.name, this.servingGram, this.waterMl);
}

/// 주식 (밥/죽) — 하나만 선택
const List<FoodItem> stapleFoods = [
  FoodItem('밥', 230, 146),
  FoodItem('진밥', 310, 197),
  FoodItem('된죽', 400, 287),
  FoodItem('죽', 400, 307),
  FoodItem('미음', 400, 327),
];

/// 국
const FoodItem soupFood = FoodItem('국', 200, 180);

/// 반찬 — 여러 칸에서 선택 (없음 포함)
const List<FoodItem> sideFoods = [
  FoodItem('고기', 70, 45),
  FoodItem('생선', 70, 47),
  FoodItem('계란', 55, 41),
  FoodItem('두부', 80, 68),
  FoodItem('포기김치', 110, 102),
  FoodItem('물김치', 80, 76.9),
];

/// 수분 · 유제품 (음료) — 물 포함
const List<FoodItem> drinkFoods = [
  FoodItem('물 한컵', 200, 200),
  FoodItem('우유', 200, 174.8),
  FoodItem('호상요구르트', 85, 69.4),
  FoodItem('액상요구르트', 100, 83.2),
  FoodItem('두유', 190, 169.1),
];

/// 기타 섭취 (과일)
const List<FoodItem> fruitFoods = [
  FoodItem('자두', 150, 127.5),
  FoodItem('바나나', 50, 45.2),
  FoodItem('키위', 80, 67.7),
  FoodItem('토마토', 350, 324.4),
  FoodItem('방울토마토', 300, 276.9),
  FoodItem('배', 110, 95.7),
  FoodItem('오렌지', 100, 86.8),
  FoodItem('귤', 120, 70.5),
  FoodItem('천도복숭아', 150, 136),
  FoodItem('참외', 150, 129.1),
  FoodItem('사과', 80, 68.1),
  FoodItem('수박', 150, 136),
  FoodItem('단감', 50, 42.8),
  FoodItem('딸기', 150, 134.5),
  FoodItem('포도', 80, 67.6),
  FoodItem('블루베리', 80, 69.2),
  FoodItem('멜론', 120, 105.7),
  FoodItem('파인애플', 200, 169.8),
];

/// 섭취 비율 선택지 (라벨 → 배율)
const List<MapEntry<String, double>> intakeRatios = [
  MapEntry('0', 0),
  MapEntry('1/4', 0.25),
  MapEntry('1/3', 0.33),
  MapEntry('1/2', 0.5),
  MapEntry('전체', 1.0),
];

/// 이름으로 품목 찾기 (없으면 null)
FoodItem? findFood(List<FoodItem> list, String name) {
  for (final f in list) {
    if (f.name == name) return f;
  }
  return null;
}

/// I/O 밸런스 정상 범위 (± ml). 이 범위를 벗어나면 알림.
const int ioBalanceThresholdMl = 500;
