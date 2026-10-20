import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/floor_map.dart';

/// 층 도면 위에 로봇이 지금 어디쯤 가고 있는지 찍는다.
///
/// 로봇은 움직이는 동안 2초마다 좌표를 올린다. 그대로 찍으면 점이 2초마다
/// 한 뼘씩 튀어 보기 나쁘고, 멈춘 건지 끊긴 건지도 구분이 안 된다. 그래서
/// 새 좌표가 오면 그 자리까지 2초에 걸쳐 미끄러뜨린다 — 로봇이 실제로
/// 움직이는 속도와 같아서 자연스럽다.
class RobotMapView extends StatefulWidget {
  const RobotMapView({super.key});

  @override
  State<RobotMapView> createState() => _RobotMapViewState();
}

class _RobotMapViewState extends State<RobotMapView> {
  /// 이보다 소식이 없으면 점을 흐리게 한다.
  ///
  /// 로봇 생사 판정(2분)과 일부러 다른 시간 축이다. 병동 와이파이가 잠깐
  /// 흔들리면 좌표가 끊기는데, 그때마다 "로봇 죽었다"고 할 수는 없다.
  /// 점만 흐려 두면 "지금 보이는 자리가 최신은 아니다" 가 전해진다.
  static const Duration _fresh = Duration(seconds: 10);

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 새 좌표가 안 와도 '얼마나 지났는지' 는 변한다. 스트림만 보고 있으면
    // 흐려질 때를 놓친다. Firestore 를 더 읽지는 않는다.
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, FloorMap>>(
      stream: FloorMap.watch(),
      initialData: FloorMap.builtIn,
      builder: (context, mapsSnap) {
        final maps = mapsSnap.data ?? FloorMap.builtIn;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('robot_state')
              .doc('current')
              .snapshots(),
          builder: (context, snap) {
            final pose = RobotPose.fromDoc(snap.data?.data());
            // 지도 이름으로 보정값을 고른다. 모르는 지도면 점을 안 찍는다.
            final floor = pose == null ? null : maps[pose.map];
            final spot = (pose == null || floor == null)
                ? null
                : floor.toPixel(pose.x, pose.y);

            // 로봇이 어느 지도에 있든, 아는 지도가 하나면 그 그림은 띄운다.
            // 그림이 없으면 화면이 통째로 비어 무슨 기능인지 알 수 없다.
            final shown = floor ?? maps['ward_edit'] ?? FloorMap.builtIn['ward_edit']!;

            final age = pose?.at == null
                ? null
                : DateTime.now().difference(pose!.at!);
            final stale = age == null || age > _fresh;

            return _frame(
              context,
              shown,
              spot,
              stale,
              _note(snap, pose, floor, spot),
            );
          },
        );
      },
    );
  }

  /// 점이 안 보일 때 왜 안 보이는지 한 줄로. 빈 지도만 띄워 두면
  /// 고장인지 원래 그런 건지 알 수가 없다.
  String? _note(
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap,
    RobotPose? pose,
    FloorMap? floor,
    ({double x, double y})? spot,
  ) {
    if (!snap.hasData) return '로봇 위치를 불러오는 중…';
    if (pose == null) return '로봇이 아직 자기 위치를 찾는 중입니다';
    if (floor == null) return '다른 지도에서 움직이는 중입니다 (${pose.map})';
    if (spot == null) return '로봇이 도면 밖에 있습니다 — 지도 보정을 확인해 주세요';
    return null;
  }

  Widget _frame(
    BuildContext context,
    FloorMap floor,
    ({double x, double y})? spot,
    bool stale,
    String? note,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // 그림을 가로폭에 맞춰 통째로 보여 준다. 잘라내면 로봇이
              // 잘린 쪽으로 갔을 때 사라진다.
              final scale = c.maxWidth / floor.imageWidth;
              final h = floor.imageHeight * scale;
              return SizedBox(
                width: c.maxWidth,
                height: h,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(floor.asset, fit: BoxFit.fill),
                    ),
                    if (spot != null)
                      AnimatedPositioned(
                        // 로봇이 2초마다 올리니 2초에 걸쳐 미끄러진다.
                        duration: const Duration(seconds: 2),
                        curve: Curves.linear,
                        left: spot.x * scale - 13,
                        top: spot.y * scale - 13,
                        child: _Dot(faded: stale),
                      ),
                  ],
                ),
              );
            },
          ),
          if (note != null)
            Container(
              width: double.infinity,
              color: AppColors.pageBg,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                note,
                style: const TextStyle(
                  color: AppColors.inkDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  /// 한동안 새 좌표가 안 왔다. 자리는 맞을 수도 있지만 최신은 아니다.
  final bool faded;

  const _Dot({required this.faded});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.42 : 1,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.danger,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.35),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
