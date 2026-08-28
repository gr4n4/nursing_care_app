import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';

/// 알림 종류별 표시 규칙.
///
/// 알림 기록 화면과 종 패널이 각자 `kind == 'meal'` 이냐 아니냐로만 갈라
/// 낙상까지 물방울로 그려졌다. 규칙을 한 곳에 두어 어긋나지 않게 한다.
///
/// 낙상·걸터앉음은 Material 아이콘에 마땅한 게 없어 자세 픽토그램 시안에서
/// 가져온 SVG 를 쓴다. 잠금화면 푸시 아이콘(web/icons/notify-*.png)도 같은
/// 그림을 옮긴 것이라 앱과 알림이 같은 모양으로 보인다.
class NotificationKind {
  /// Material 아이콘을 쓰는 종류(식사·배설)에만 있다.
  final IconData? icon;

  /// SVG 픽토그램을 쓰는 종류(낙상·걸터앉음)에만 있다.
  final String? svgAsset;

  final Color color;
  final Color background;

  /// 즉시 조치가 필요한 종류인지. 목록에서 강조할지 판단에 쓴다.
  final bool critical;

  const NotificationKind._({
    this.icon,
    this.svgAsset,
    required this.color,
    required this.background,
    this.critical = false,
  });

  static const _meal = NotificationKind._(
    icon: Icons.restaurant_rounded,
    color: AppColors.brand,
    background: AppColors.brandSoft,
  );

  static const _output = NotificationKind._(
    icon: Icons.water_drop_rounded,
    color: AppColors.fluid,
    background: Color(0xFFE3EEFB),
  );

  static const _fall = NotificationKind._(
    svgAsset: 'assets/icon/alert-fall.svg',
    color: AppColors.danger,
    background: AppColors.dangerBg,
    critical: true,
  );

  static const _bedside = NotificationKind._(
    svgAsset: 'assets/icon/alert-bedside.svg',
    color: AppColors.warn,
    background: AppColors.warnBg,
    critical: true,
  );

  static const _unknown = NotificationKind._(
    icon: Icons.notifications_rounded,
    color: AppColors.inkMid,
    background: Color(0xFFEEF1F6),
  );

  static NotificationKind of(String? kind) {
    switch (kind) {
      case 'meal':
        return _meal;
      case 'output':
        return _output;
      case 'fall':
        return _fall;
      case 'bedside':
        return _bedside;
      default:
        return _unknown;
    }
  }

  /// 종류에 맞는 그림. Material 아이콘이든 SVG 든 부르는 쪽은 같게 쓴다.
  Widget glyph({double size = 18, Color? tint}) {
    final c = tint ?? color;
    if (svgAsset != null) {
      return SvgPicture.asset(
        svgAsset!,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      );
    }
    return Icon(icon, size: size, color: c);
  }
}
