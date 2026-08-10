/// 간호일(care-day) 날짜 계산 유틸.
///
/// 요양/병동의 I/O(섭취·배설) 기록은 자정이 아니라 간호 근무 기준으로
/// 하루를 끊는다. 여기서는 매일 오전 7시를 하루의 시작으로 본다.
/// 예) 07:00 ~ 다음날 06:59 = 같은 간호일.
///
/// 이렇게 하면 밤 늦게 섭취한 수분과 새벽에 나온 배설이 같은 날로 묶여서
/// 수분 밸런스 계산이 어긋나지 않는다.
library;

/// 간호일 경계 시각(시). 이 값만 바꾸면 하루 기준 시각이 바뀐다.
const int careDayStartHour = 7;

/// 주어진 시각이 속한 '간호일'의 달력 날짜(자정)를 반환.
DateTime careDayOf(DateTime dt) {
  final shifted = dt.subtract(const Duration(hours: careDayStartHour));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Firestore 저장/조회용 날짜 키. 예: 2026-07-01
String careDateKey(DateTime dt) {
  final d = careDayOf(dt);
  return '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 화면 표시용 날짜. 예: 2026.07.01
String careDateDisplay(DateTime dt) {
  final d = careDayOf(dt);
  return '${d.year}.'
      '${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 간호일 기준 요일. 예: 월
String careWeekday(DateTime dt) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  // DateTime.weekday: 월요일=1 ... 일요일=7
  return days[careDayOf(dt).weekday - 1];
}

/// 실제 벽시계 시각(HH:mm). 기록의 'time' 필드에 쓰는 값은 간호일과 무관하게
/// 실제 시각을 그대로 남긴다.
String wallClockTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
