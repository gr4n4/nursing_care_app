import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 로봇 좌표(m)를 층 도면 그림의 픽셀로 옮긴다.
///
/// 로봇은 자기가 라이다로 만든 점유격자 위에서 움직이고, 화면에 띄우는 것은
/// 비상대피도다. 같은 층을 그린 다른 그림이라 좌표계가 다르다.
///
/// 왜 도면을 쓰는가: 점유격자에는 정수기도 세탁 카트도 찍혀 있고 유리벽은
/// 비어 있다. 흠이 아니라 그게 맞다 — 센서가 보는 대로여야 로봇이 자기
/// 위치를 찾는다. 다만 사람이 보기에는 대피도가 낫다.
///
/// **아핀이어야 한다.** 대피도는 보기 좋게 다듬은 그림이라 가로와 세로
/// 배율이 다르다 — 병동 2.9%, 연구소 3.2%. 회전과 한 가지 배율만 쓰는
/// 닮음변환으로는 아무리 돌리고 키워도 안 맞는다.
///
/// 보정 과정과 검증 그림은 `maps/README.md` 에 있다.
@immutable
class FloorMap {
  /// 로봇이 `robot_state/current.map` 에 올리는 이름과 같아야 한다.
  final String mapName;

  /// 화면에 띄울 그림.
  final String asset;

  final int imageWidth;
  final int imageHeight;

  /// px = a·x + b·y + c,  py = d·x + e·y + f
  final double a, b, c, d, e, f;

  const FloorMap({
    required this.mapName,
    required this.asset,
    required this.imageWidth,
    required this.imageHeight,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.e,
    required this.f,
  });

  /// 2026-10-20 에 맞춘 값.
  ///
  /// 설정 문서를 못 읽어도 지도는 떠야 해서 코드에도 둔다. Firestore 에
  /// `settings/floor_maps` 가 있으면 그쪽이 이긴다 — 로봇이 지도를 다시
  /// 만들면 `origin` 이 바뀌어 이 값이 통째로 깨지는데, 그때 앱을 다시
  /// 배포하지 않고 고칠 수 있어야 한다.
  static const Map<String, FloorMap> builtIn = {
    'ward_edit': FloorMap(
      mapName: 'ward_edit',
      asset: 'assets/map/ward_4f.png',
      imageWidth: 1672,
      imageHeight: 941,
      a: 4.75175, b: -20.85230, c: 678.16,
      d: -20.16562, e: -4.47570, f: 464.72,
    ),
    // 연구소는 시험용이다. 벽이 유리라 라이다에 거의 안 잡혀서, 병동만큼
    // 정확하지 않다. "로봇이 고리 복도를 돌고 있다" 를 보는 데 쓴다.
    'lab_4F': FloorMap(
      mapName: 'lab_4F',
      asset: 'assets/map/lab_4f.png',
      imageWidth: 1672,
      imageHeight: 941,
      a: -31.00918, b: 36.00200, c: 1203.33,
      d: 34.86241, e: 27.24518, f: 368.75,
    ),
  };

  /// 로봇 좌표(m) → 도면 픽셀. 그림 밖이면 null.
  ///
  /// 밖으로 나가는 것은 보통 지도를 다시 만들어 보정이 깨진 경우다. 그때는
  /// 엉뚱한 자리에 점을 찍느니 아무것도 안 찍는 편이 낫다 — 틀린 자리에
  /// 찍힌 점은 없는 점보다 나쁘다.
  ({double x, double y})? toPixel(double rx, double ry) {
    final px = a * rx + b * ry + c;
    final py = d * rx + e * ry + f;
    if (px < 0 || px > imageWidth || py < 0 || py > imageHeight) return null;
    return (x: px, y: py);
  }

  static FloorMap? _one(String name, Map<String, dynamic> m) {
    final t = m['transform'];
    if (t is! Map) return null;
    double? n(dynamic v) => (v is num) ? v.toDouble() : null;
    final a = n(t['a']), b = n(t['b']), c = n(t['c']);
    final d = n(t['d']), e = n(t['e']), f = n(t['f']);
    if (a == null || b == null || c == null) return null;
    if (d == null || e == null || f == null) return null;
    final base = builtIn[name];
    final w = m['imageWidth'], h = m['imageHeight'];
    final asset = (m['asset'] ?? base?.asset ?? '').toString();
    if (asset.isEmpty) return null;
    return FloorMap(
      mapName: name,
      asset: asset,
      imageWidth: w is num ? w.toInt() : (base?.imageWidth ?? 0),
      imageHeight: h is num ? h.toInt() : (base?.imageHeight ?? 0),
      a: a, b: b, c: c, d: d, e: e, f: f,
    );
  }

  /// 설정 문서는 지도 이름을 열쇠로 하는 묶음이다. 한 지도만 틀어져도
  /// 나머지는 살아 있어야 해서, 읽히는 것만 받고 나머지는 코드 값을 쓴다.
  static Map<String, FloorMap> fromDoc(Map<String, dynamic>? data) {
    final out = Map<String, FloorMap>.from(builtIn);
    final maps = data?['maps'];
    if (maps is Map) {
      maps.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          final m = _one(k.toString(), v);
          if (m != null) out[k.toString()] = m;
        }
      });
    }
    return out;
  }

  static Stream<Map<String, FloorMap>> watch() => FirebaseFirestore.instance
      .doc('settings/floor_maps')
      .snapshots()
      .map((s) => fromDoc(s.data()))
      .handleError((Object e) {
        debugPrint('층 도면 설정 구독 실패: $e');
      });
}

/// 로봇이 지금 어디에 있는가. `robot_state/current` 한 문서를 읽은 결과.
@immutable
class RobotPose {
  final double x;
  final double y;

  /// 어느 지도 위의 좌표인가(`ward_edit` / `lab_4F`).
  ///
  /// 이 이름으로 보정값을 고른다. 이름이 안 맞으면 점을 안 그린다 —
  /// 연구소 좌표를 병동 도면에 그리면 두 지도의 원점이 달라 복도 밖에
  /// 로봇이 찍힌다. 실제로 그렇게 보여서 "지도가 연결이 안 됐나" 하는
  /// 혼란이 있었다.
  final String map;

  final DateTime? at;

  const RobotPose({
    required this.x,
    required this.y,
    required this.map,
    this.at,
  });

  static RobotPose? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final p = d['pose'];
    // pose 가 null 인 것은 고장이 아니다. 로봇이 아직 자기 위치를 못 찾은
    // 것뿐이라, 조용히 점만 안 그린다.
    if (p is! Map) return null;
    final x = p['x'], y = p['y'];
    if (x is! num || y is! num) return null;
    return RobotPose(
      x: x.toDouble(),
      y: y.toDouble(),
      map: (d['map'] ?? '').toString(),
      at: _time(d['updatedAt']),
    );
  }

  static DateTime? _time(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
