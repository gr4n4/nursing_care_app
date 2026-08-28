import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 알림 종류별 표시 규칙.
///
/// 알림 기록 화면과 종 패널이 각자 `kind == 'meal'` 이냐 아니냐로만 갈라
/// 낙상까지 물방울로 그려졌다. 규칙을 한 곳에 두어 어긋나지 않게 한다.
class NotificationKind {
  final IconData icon;
  final Color color;
  final Color background;

  /// 즉시 조치가 필요한 종류인지. 목록에서 강조할지 판단에 쓴다.
  final bool critical;

  const NotificationKind._({
    required this.icon,
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
    icon: Icons.personal_injury_rounded,
    color: AppColors.danger,
    background: AppColors.dangerBg,
    critical: true,
  );

  static const _bedside = NotificationKind._(
    icon: Icons.airline_seat_flat_rounded,
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
}
