import 'package:flutter/material.dart';

/// NRCarec 색 팔레트 — 앱 전체가 참조하는 단일 출처.
///
/// 이전에는 페이지마다 `static const Color mintDark = Color(0xFF0F766E)` 식으로
/// 같은 값을 12개 파일에 따로 선언해 두어, 색을 바꾸려면 전부 손대야 했다.
/// 여기 모아 두면 한 곳만 고치면 되고, 다크모드도 이 위에 얹을 수 있다.
///
/// 대비는 WCAG 2.1 상대휘도로 실측했다(기준: 본문 4.5:1, 최고 7:1).
class AppColors {
  const AppColors._();

  // ── 브랜드(네이비) ─────────────────────────────
  // 아이콘의 남색에서 뽑았다. 흰 글씨 대비 12.97:1(AAA).
  // 이전 민트(#7CCFC6)는 흰 글씨 대비가 1.81:1로 기준 미달이었다.
  static const Color brand = Color(0xFF16305E);

  /// 그라데이션 헤더의 밝은 쪽 끝. 단독으로 쓰지 않는다.
  static const Color brandLight = Color(0xFF22437C);

  /// 눌림·강조 상태.
  static const Color brandDeep = Color(0xFF0E2144);

  /// 링크·포커스처럼 작고 눈에 띄어야 하는 요소.
  static const Color interactive = Color(0xFF2A4C86);

  /// 칩·선택 배경. 이 위에는 brand 색 글씨를 얹는다(대비 14.6:1).
  static const Color brandSoft = Color(0xFFDCE7F5);

  /// brandSoft 면의 테두리.
  static const Color brandSoftBorder = Color(0xFFC3D5EE);

  // ── 상태색 ────────────────────────────────────
  // 브랜드 색과 반드시 구분되어야 한다. 관제 화면에서 '조치가 필요한가'는
  // 브랜드가 아니라 이 색들이 답한다.
  static const Color ok = Color(0xFF0F766E);
  static const Color warn = Color(0xFFB45309);
  static const Color danger = Color(0xFFDC2626);
  static const Color cleared = Color(0xFF15803D);

  static const Color okBg = Color(0xFFE4F3F1);
  static const Color warnBg = Color(0xFFFBF0DF);
  static const Color dangerBg = Color(0xFFFCE9E9);

  // ── 중립 ──────────────────────────────────────
  // 순회색이 아니라 브랜드 쪽으로 살짝 기울인 청회색이다.
  static const Color pageBg = Color(0xFFF4F6FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color raised = Color(0xFFFAFBFE);
  static const Color line = Color(0xFFDDE3EE);

  /// 표에서 섭취/배설 덩어리를 가르는 굵은 선.
  static const Color divider = Color(0xFF94A3B8);

  static const Color ink = Color(0xFF101B2E);
  static const Color inkMid = Color(0xFF4A5768);
  static const Color inkDim = Color(0xFF8B97A8);

  // ── 분류 표시색 ────────────────────────────────
  // 부종/배변타입처럼 '종류'를 나타내는 표식. 상태(정상·주의)와는 다르다.
  static const Color edema = Color(0xFF7C3AED);
  static const Color stool = Color(0xFF0F766E);
  static const Color fluid = Color(0xFF2563EB);

  /// 헤더 그라데이션. 페이지마다 따로 쓰던 값을 한 곳으로 모았다.
  static const LinearGradient headerGradient = LinearGradient(
    colors: [brand, brandLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
