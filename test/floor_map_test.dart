import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/utils/floor_map.dart';

/// 로봇 좌표를 도면 픽셀로 옮기는 값이 맞는지 못 박아 둔다.
///
/// 이 값이 틀어지면 분석기도 테스트도 조용히 지나가고, 병동에서 로봇이
/// 엉뚱한 자리에 찍히는 것으로만 드러난다. 실제로 한 번 복도를 따라 11 m
/// 밀린 값을 맞다고 본 적이 있다.
void main() {
  final ward = FloorMap.builtIn['ward_edit']!;

  group('병동 보정', () {
    test('간호사실 카운터가 도면의 간호사실 상자 안에 찍힌다', () {
      // 보정을 못 박은 지표. 점유격자 (250,821) 칸이 카운터고,
      // 미터로는 (-3.4, -16.2) 다. 도면의 간호사실 상자는 (여백을 잘라낸
      // 뒤 기준으로) x 790~1006, y 456~521.
      //
      // 상자 '중심' 이 아니라 '안' 을 본다. 못으로 쓴 두 점은 서로 다른
      // 것의 중심이다 — 하나는 라이다가 본 카운터, 하나는 사람이 그린
      // 상자라 몇 px 어긋나는 게 정상이다. 그래서 복도 양쪽 벽을 80군데
      // 넘게 재서 고르게 맞춘 뒤, 못은 상자 안에 들기만 하면 된 것으로 본다.
      final p = ward.toPixel(-3.4, -16.2);
      expect(p, isNotNull);
      expect(p!.x, inInclusiveRange(790, 1006));
      expect(p.y, inInclusiveRange(456, 521));
    });

    test('모든 waypoint 가 도면 안에 들어온다', () {
      // 로봇팀이 준 실측 좌표. 하나라도 밖으로 나가면 그 병실로 갈 때
      // 점이 사라진다. 427 은 건물 외곽선보다 바깥이라 도면 여백을
      // 잘라낼 때 실제로 한 번 잘려 나갔다.
      const pts = <String, List<double>>{
        '420': [-4.484, -0.332], '421': [-5.538, 4.411],
        '422': [-6.388, 8.161],  '423': [-6.737, 9.452],
        '424': [-5.463, 11.648], '425': [-3.913, 4.698],
        '426': [5.337, -38.852], '427': [8.150, -44.350],
        '428': [3.511, -38.055], '429': [2.761, -32.922],
        '430': [0.862, -26.089],
        'park': [-0.100, -1.900], 'loading': [-2.350, -12.850],
      };
      pts.forEach((name, v) {
        expect(ward.toPixel(v[0], v[1]), isNotNull, reason: '$name 이 도면 밖');
      });
    });

    test('도면 밖은 안 찍는다', () {
      // 지도를 다시 만들면 origin 이 바뀌어 좌표가 엉뚱해진다. 그때
      // 틀린 자리에 찍힌 점은 없는 점보다 나쁘다.
      expect(ward.toPixel(9999, 9999), isNull);
      expect(ward.toPixel(-9999, -9999), isNull);
    });

    test('가로세로 배율이 서로 다르다', () {
      // 대피도가 보기 좋게 다듬은 그림이라 2.9% 어긋나 있다. 닮음변환으로
      // 맞추려다 못 맞춘 적이 있어, 아핀인 것을 값으로 남긴다.
      final sx = ward.a.abs() + ward.d.abs();
      final sy = ward.b.abs() + ward.e.abs();
      expect(sx, isNot(closeTo(sy, 0.01)));
    });
  });

  group('화살표 방향', () {
    // 로봇이 420 에서 430 쪽(복도 동쪽)을 보고 있을 때의 yaw.
    // 두 waypoint 를 잇는 방향이다.
    final alongCorridor = math.atan2(-26.089 - (-0.332), 0.862 - (-4.484));

    test('복도를 따라 보면 도면에서도 가로로 눕는다', () {
      // 병동 복도는 도면에서 거의 수평이고, 430 은 420 의 오른쪽이다.
      // 화살표가 오른쪽(+x)을 가리켜야 한다.
      final h = ward.headingOnImage(alongCorridor);
      expect(h.abs(), lessThan(0.12), reason: '수평에서 7도 넘게 벗어남');
    });

    test('yaw 를 그대로 쓰지 않는다', () {
      // 점유격자가 도면에 대해 78도쯤 돌아가 있다. 변환을 빠뜨리면
      // 화살표가 엉뚱한 데를 가리키는데, 화면만 봐서는 알아채기 어렵다.
      expect((ward.headingOnImage(0) - 0).abs(), greaterThan(1.0));
    });

    test('90도 돌리면 화면에서도 90도 돌아간다', () {
      double diff(double a, double b) {
        var t = a - b;
        while (t > math.pi) {
          t -= 2 * math.pi;
        }
        while (t < -math.pi) {
          t += 2 * math.pi;
        }
        return t.abs();
      }

      final d = diff(
        ward.headingOnImage(math.pi / 2),
        ward.headingOnImage(0),
      );
      // 가로·세로 배율이 3% 달라 정확히 90도는 아니다.
      expect(d, closeTo(math.pi / 2, 0.06));
    });
  });

  group('설정으로 덮어쓰기', () {
    test('문서가 없으면 코드에 둔 값을 쓴다', () {
      final m = FloorMap.fromDoc(null);
      expect(m['ward_edit']!.a, ward.a);
      expect(m.containsKey('lab_4F'), isTrue);
    });

    test('한 지도만 고쳐도 나머지는 그대로다', () {
      // 지도를 다시 만들면 앱 재배포 없이 고칠 수 있어야 한다.
      final m = FloorMap.fromDoc({
        'maps': {
          'ward_edit': {
            'transform': {'a': 1.0, 'b': 0.0, 'c': 2.0,
                          'd': 0.0, 'e': 1.0, 'f': 3.0},
          },
        },
      });
      expect(m['ward_edit']!.a, 1.0);
      expect(m['ward_edit']!.asset, ward.asset); // 빠진 값은 코드 것을 쓴다
      expect(m['lab_4F']!.a, FloorMap.builtIn['lab_4F']!.a);
    });

    test('깨진 설정은 무시하고 코드 값을 지킨다', () {
      final m = FloorMap.fromDoc({'maps': {'ward_edit': {'transform': 'x'}}});
      expect(m['ward_edit']!.a, ward.a);
    });
  });

  group('로봇 위치 읽기', () {
    test('pose 가 없으면 null — 고장이 아니다', () {
      // 자기 위치를 아직 못 찾은 것뿐이라 조용히 점만 안 그린다.
      expect(RobotPose.fromDoc({'map': 'ward_edit'}), isNull);
      expect(RobotPose.fromDoc({'pose': null}), isNull);
    });

    test('지도 이름을 같이 읽는다', () {
      // 이름이 안 맞으면 점을 안 그린다. 연구소 좌표를 병동 도면에 그리면
      // 원점이 달라 복도 밖에 찍힌다.
      final p = RobotPose.fromDoc({
        'pose': {'x': -3.4, 'y': -16.2},
        'map': 'ward_edit',
        'updatedAt': '2026-10-20T01:02:03+00:00',
      });
      expect(p, isNotNull);
      expect(p!.map, 'ward_edit');
      expect(p.at, isNotNull);
    });
  });
}
