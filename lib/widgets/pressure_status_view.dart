import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 압력 센서의 임계값과 연결 상태를 **보여주기만** 한다.
///
/// 바꾸는 곳은 압력 대시보드다. 여기서도 고칠 수 있게 하면 같은 값의 원본이
/// 둘이 되어, 어긋났을 때 무엇이 맞는지 정할 수 없다. 다만 간호사가 "지금
/// 몇으로 돼 있나"를 NRCarec 한 곳에서 볼 수 있어야 해서 값만 비춘다.
///
/// 압력 서버가 settings/pressure_status 에 흘려 보낸 것을 읽는다.
class PressureStatusView extends StatelessWidget {
  const PressureStatusView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('pressure_status')
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        return _box(
          child: data == null ? _notConnected() : _status(data),
        );
      },
    );
  }

  Widget _box({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }

  /// 압력 서버가 아직 한 번도 값을 올리지 않은 상태.
  /// 알림을 켜 두어도 보낼 쪽이 없으면 아무 일도 일어나지 않으므로 알린다.
  Widget _notConnected() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 16, color: AppColors.inkDim),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '압력 서버가 아직 연결되지 않았습니다',
                style: TextStyle(
                  color: AppColors.inkMid,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '병동 PC 의 압력 서버가 켜지면 여기에 기준과 센서 수가 보입니다.',
          style: TextStyle(
            color: AppColors.inkDim,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _status(Map<String, dynamic> data) {
    final pressure = data['criticalPressure'];
    final minutes = data['criticalTime'];
    final sensors = (data['sensors'] as List<dynamic>?) ?? const [];
    final total = sensors.length;
    final offline = sensors
        .where((s) => (s as Map)['connected'] == false)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('위험 판정 기준', _threshold(pressure, minutes)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
        _line(
          '연결된 센서',
          total == 0
              ? '없음'
              : (offline == 0 ? '$total대 모두 연결됨' : '$total대 · $offline대 끊김'),
          // 끊긴 센서는 감시가 멈춘 것이라 눈에 띄어야 한다.
          valueColor: offline > 0 ? AppColors.danger : null,
        ),
        const SizedBox(height: 9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.inkDim),
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '이 값은 보기만 합니다. 바꾸려면 압력 대시보드 → 위험 감지 설정에서 고치세요.',
                style: TextStyle(
                  color: AppColors.inkDim,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _threshold(Object? pressure, Object? minutes) {
    final p = pressure is num ? '${_trim(pressure)} mmHg' : null;
    final m = minutes is num ? '${_trim(minutes)}분 누적' : null;
    if (p == null && m == null) return '알 수 없음';
    return [p, m].whereType<String>().join(' · ');
  }

  /// 32.0 을 '32' 로. 소수점이 의미 있을 때만 남긴다.
  String _trim(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _line(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.inkMid,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
