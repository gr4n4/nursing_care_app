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

    // connected 는 세 가지다 — true/false/null.
    //
    // null 은 "서버는 아는 센서인데 아직 한 번도 접속하지 않음"이다. 라즈베리
    // 파이를 안 켰거나 네트워크가 안 닿는 경우가 여기 해당한다. false 만
    // 끊김으로 세면 그 센서가 '연결됨'으로 보여, 감시가 시작조차 안 됐는데
    // 괜찮은 줄 알게 된다. 병동에서 제일 위험한 오표시라 따로 센다.
    final offline =
        sensors.where((s) => (s as Map)['connected'] == false).length;
    final unknown =
        sensors.where((s) => (s as Map)['connected'] == null).length;
    final ok = total - offline - unknown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('위험 판정 기준', _threshold(pressure, minutes)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
        _line(
          '센서',
          _sensorText(total, ok, offline, unknown),
          // 끊긴 센서는 감시가 멈춘 것, 알 수 없는 센서는 시작조차 안 된
          // 것이다. 둘 다 눈에 띄어야 한다.
          valueColor: offline > 0
              ? AppColors.danger
              : (unknown > 0 ? AppColors.warn : null),
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

  /// '5대 모두 연결됨' / '5대 · 1대 끊김' / '5대 · 2대 확인 중'.
  ///
  /// 끊김과 확인 중을 모두 적는다. 둘의 뜻이 다르다 — 끊김은 돌던 것이
  /// 멈춘 것이고, 확인 중은 아직 시작도 안 된 것이다.
  String _sensorText(int total, int ok, int offline, int unknown) {
    if (total == 0) return '없음';
    if (offline == 0 && unknown == 0) return '$total대 모두 연결됨';
    final parts = [
      if (ok > 0) '$ok대 연결됨',
      if (offline > 0) '$offline대 끊김',
      if (unknown > 0) '$unknown대 확인 중',
    ];
    return '$total대 · ${parts.join(' · ')}';
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
