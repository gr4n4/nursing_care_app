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
      // 미터로는 (-3.4, -16.2) 다. 도면의 간호사실 상자는
      // x 892~1108, y 572~637.
      //
      // 상자 '중심' 이 아니라 '안' 을 본다. 못으로 쓴 두 점은 서로 다른
      // 것의 중심이다 — 하나는 라이다가 본 카운터, 하나는 사람이 그린
      // 상자라 몇 px 어긋나는 게 정상이다. 그래서 복도 양쪽 벽을 80군데
      // 넘게 재서 고르게 맞춘 뒤, 못은 상자 안에 들기만 하면 된 것으로 본다.
      final p = ward.toPixel(-3.4, -16.2);
      expect(p, isNotNull);
      expect(p!.x, inInclusiveRange(892, 1108));
      expect(p.y, inInclusiveRange(572, 637));
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
