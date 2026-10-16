import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/models/delivery_request.dart';

/// 로봇 쪽(colcon_ws_jy/scripts/nrcarec_bridge.py)과 맞춰 둔 약속.
///
/// 여기서 어긋나면 분석기도 테스트도 조용히 지나가고, 병동에서 간호사가
/// 버튼을 눌렀을 때 Firestore 가 거부하는 것으로만 드러난다. 그때는 로봇이
/// 복도에 선 채다. 그래서 값으로 못 박아 둔다.
void main() {
  /// 보안 규칙이 앱에 열어 준 상태. firestore.rules 의 목록과 같아야 한다.
  const writable = {'accepted', 'delivering', 'done', 'canceled'};

  test('사람이 누르는 버튼은 앱이 쓸 수 있는 상태만 만든다', () {
    for (final s in [
      DeliveryStatus.requested,
      DeliveryStatus.accepted,
      DeliveryStatus.atLoading,
      DeliveryStatus.delivering,
      DeliveryStatus.delivered,
      DeliveryStatus.done,
      DeliveryStatus.closed,
    ]) {
      final next = DeliveryStatus.nextAction(s)?.next;
      if (next == null) continue;
      expect(
        writable,
        contains(next),
        reason: '$s 에서 $next 로 넘기는 버튼은 보안 규칙에 막힌다',
      );
    }
  });

  test('도착한 건은 수령 완료로만 넘어간다', () {
    // 이 버튼이 눌리지 않으면 로봇이 대기 자리로 돌아가지 못한다.
    expect(
      DeliveryStatus.nextAction(DeliveryStatus.delivered)?.next,
      DeliveryStatus.done,
    );
  });

  test('도착 · 수령 대기도 진행 중으로 센다', () {
    // 폰은 이 목록으로 조회한다. delivered 가 빠지면 받아 갈 것이 있는데도
    // 폰에 아무것도 안 뜬다.
    expect(DeliveryStatus.active, contains(DeliveryStatus.delivered));
    expect(DeliveryStatus.active, contains(DeliveryStatus.done));
    expect(DeliveryStatus.active, isNot(contains(DeliveryStatus.closed)));
  });

  group('로봇 신호 끊김 판정', () {
    final now = DateTime(2026, 10, 16, 9, 0);

    test('60초마다 오는 신호를 한 번 빠뜨린 것은 넘겨 준다', () {
      expect(
        RobotState.isStale(now.subtract(const Duration(seconds: 90)), now: now),
        isFalse,
      );
    });

    test('2분을 넘기면 끊긴 것으로 본다', () {
      expect(
        RobotState.isStale(
            now.subtract(const Duration(minutes: 2, seconds: 1)),
            now: now),
        isTrue,
      );
    });

    test('모르는 것은 끊긴 것으로 세지 않는다', () {
      // 값이 없는 것과, 이 PC 시계가 뒤로 틀어져 미래로 보이는 것.
      expect(RobotState.isStale(null, now: now), isFalse);
      expect(
        RobotState.isStale(now.add(const Duration(hours: 1)), now: now),
        isFalse,
      );
    });
  });
}
