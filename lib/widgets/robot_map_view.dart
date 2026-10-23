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

  /// 지도가 차지할 수 있는 최대 높이.
  ///
  /// 안 막으면 도면이 가로폭을 꽉 채우며 세로로도 같이 커져서, 배차 화면에
  /// 들어오자마자 요청 목록이 화면 밖으로 밀려난다. 배차 화면의 주인공은
  /// 요청 목록이고 지도는 곁들이다.
  static const double _maxHeight = 320;

  Timer? _tick;
  bool _open = true;

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
            final d = snap.data?.data();

            // 어느 층 그림을 띄울지는 **좌표와 상관없이** 지도 이름으로 고른다.
            //
            // 예전에는 pose 가 없으면 이름까지 버리고 병동으로 떨어뜨렸다.
            // 그래서 연구소에서 시험하는데 병동 도면이 떴다. 로봇이 자기
            // 위치를 못 찾는 것과 어느 층에 있는지는 별개다.
            final mapName = (d?['map'] ?? '').toString();
            final floor = maps[mapName] ?? maps['ward_edit']!;
            final known = maps.containsKey(mapName);

            final pose = RobotPose.fromDoc(d);
            final spot = (pose == null || !known)
                ? null
                : floor.toPixel(pose.x, pose.y);

            final age = pose?.at == null
                ? null
                : DateTime.now().difference(pose!.at!);

            return _frame(
              floor,
              spot,
              // 로봇이 보는 방향. 지도가 도면에 대해 돌아가 있어서 좌표와
              // 같은 변환을 거쳐야 화살표가 맞는 데를 가리킨다.
              pose?.yaw == null ? null : floor.headingOnImage(pose!.yaw!),
              age == null || age > _fresh,
              _note(snap, d, pose, mapName, known, spot),
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
    Map<String, dynamic>? d,
    RobotPose? pose,
    String mapName,
    bool known,
    ({double x, double y})? spot,
  ) {
    if (!snap.hasData) return '로봇 위치를 불러오는 중…';
    if (d == null) return '로봇이 아직 아무것도 올리지 않았습니다';
    if (!known) {
      return mapName.isEmpty
          ? '로봇이 어느 지도에 있는지 아직 모릅니다'
          : '보정하지 않은 지도입니다 ($mapName) — 병동 도면을 대신 띄웁니다';
    }
    if (pose == null) return '로봇이 아직 자기 위치를 찾는 중입니다';
    if (spot == null) return '로봇이 도면 밖에 있습니다 — 지도 보정을 확인해 주세요';
    return null;
  }

  Widget _frame(
    FloorMap floor,
    ({double x, double y})? spot,
    double? heading,
    bool stale,
    String? note,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(floor, note),
          if (_open)
            LayoutBuilder(
              builder: (context, c) {
                // 가로폭에 맞추되 높이로 한 번 더 조인다. 둘 중 작은 쪽을
                // 쓰므로 그림 전체가 늘 들어온다 — 잘라내면 로봇이 잘린
                // 쪽으로 갔을 때 사라진다.
                final scale = (c.maxWidth / floor.imageWidth)
                    .clamp(0.0, _maxHeight / floor.imageHeight);
                final w = floor.imageWidth * scale;
                final h = floor.imageHeight * scale;
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                  child: SizedBox(
                    width: w,
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
                            left: spot.x * scale - _Dot.size / 2,
                            top: spot.y * scale - _Dot.size / 2,
                            child: _Dot(heading: heading, faded: stale),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _bar(FloorMap floor, String? note) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        child: Row(
          children: [
            Icon(Icons.map_outlined, size: 17, color: AppColors.inkDim),
            const SizedBox(width: 8),
            Text(
              floor.label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.inkDim,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            Text(
              _open ? '접기' : '펼치기',
              style: const TextStyle(
                color: AppColors.inkDim,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 20,
              color: AppColors.inkDim,
            ),
          ],
        ),
      ),
    );
  }
}

/// 로봇 자리에 찍는 표시.
///
/// 레이더에 잡힌 물체처럼 파동이 퍼진다. 가만히 있는 점은 "지금 저기 있다"
/// 와 "아까 저기 있었다" 가 구분이 안 되는데, 맥이 뛰면 살아 있는 값으로
/// 읽힌다.
///
/// 방향을 아는 동안에는 화살표가 된다. 로봇이 어디를 보고 있는지가
/// 복도에서 마주칠 때 쓸모가 있다 — 오는 중인지 가는 중인지.
class _Dot extends StatefulWidget {
  /// 도면 위에서 로봇이 향한 각도(라디안). 모르면 null 이고 그때는 동그라미다.
  final double? heading;

  /// 한동안 새 좌표가 안 왔다. 자리는 맞을 수도 있지만 최신은 아니다.
  final bool faded;

  /// 파동까지 담을 네모의 한 변.
  static const double size = 64;

  const _Dot({required this.heading, required this.faded});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _Dot old) {
    super.didUpdateWidget(old);
    // 소식이 끊긴 동안에는 맥을 멈춘다. 계속 뛰면 끊긴 줄 모른다.
    if (widget.faded && _pulse.isAnimating) {
      _pulse.stop();
    } else if (!widget.faded && !_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 움직임을 줄여 달라고 한 사람에게는 파동을 안 보인다.
    final still = MediaQuery.of(context).disableAnimations || widget.faded;
    return SizedBox(
      width: _Dot.size,
      height: _Dot.size,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          painter: _DotPainter(
            heading: widget.heading,
            pulse: still ? null : _pulse.value,
            faded: widget.faded,
          ),
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  final double? heading;

  /// 0→1 을 되풀이한다. null 이면 파동을 안 그린다.
  final double? pulse;

  final bool faded;

  const _DotPainter({
    required this.heading,
    required this.pulse,
    required this.faded,
  });

  static const Color _red = Color(0xFFDC2626);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final o = faded ? 0.45 : 1.0;

    // 파동 — 두 겹을 엇갈려 퍼뜨린다. 한 겹이면 사라진 뒤 빈 틈이 생긴다.
    final p = pulse;
    if (p != null) {
      for (final phase in const [0.0, 0.5]) {
        final t = (p + phase) % 1.0;
        canvas.drawCircle(
          c,
          9 + t * 21,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * (1 - t)
            ..color = _red.withValues(alpha: (1 - t) * 0.5),
        );
      }
    }

    final fill = Paint()..color = _red.withValues(alpha: o);
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: o)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;

    if (heading == null) {
      // 방향을 모르면 동그라미. 모르는 것을 아는 척하지 않는다.
      canvas.drawCircle(c, 8, fill);
      canvas.drawCircle(c, 8, edge);
      return;
    }

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(heading!);

    // 꼬리는 둥글고 머리는 뾰족한 화살표. 가리키는 쪽이 한눈에 들어온다.
    const tail = -11.0, neck = 2.0, tip = 14.0, half = 4.6, barb = 9.0;
    final body = Path()
      ..moveTo(tail + 4, -half)
      ..lineTo(neck, -half)
      ..lineTo(neck, -barb)
      ..lineTo(tip, 0)
      ..lineTo(neck, barb)
      ..lineTo(neck, half)
      ..lineTo(tail + 4, half)
      ..arcToPoint(Offset(tail + 4, -half),
          radius: const Radius.circular(half), clockwise: true)
      ..close();
    canvas.drawPath(body, edge);
    canvas.drawPath(body, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.heading != heading || old.pulse != pulse || old.faded != faded;
}
