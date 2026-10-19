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

  group('배송 성패와 복귀 성패는 따로 센다', () {
    DeliveryRequest req({
      String status = DeliveryStatus.closed,
      String deliveryResult = '',
      String returnResult = '',
      String failCode = '',
      String failReason = '',
    }) =>
        DeliveryRequest(
          id: 'x',
          room: '425',
          items: const [],
          status: status,
          deliveryResult: deliveryResult,
          returnResult: returnResult,
          failCode: failCode,
          failReason: failReason,
        );

    test('로봇이 새 필드를 안 쓰면 예전과 똑같이 보인다', () {
      // 앱을 먼저 배포해야 해서 이 갈래가 꼭 있어야 한다. 로봇만 먼저
      // 고치면 복귀 실패가 '완료' 로 보여 지금 있는 신호마저 사라진다.
      expect(req(status: DeliveryStatus.closed).resultLabel, '완료');
      expect(req(status: DeliveryStatus.closed).deliveredOk, isTrue);
      expect(req(status: DeliveryStatus.failed).resultLabel, '실패');
      expect(req(status: DeliveryStatus.failed).deliveredOk, isFalse);
      expect(req(status: DeliveryStatus.closed).robotStranded, isFalse);
    });

    test('복귀만 실패한 건은 성공으로 센다', () {
      // 물품은 전달이 끝났다. 이걸 실패로 세면 성공률이 실제보다 나빠진다.
      final r = req(deliveryResult: 'done', returnResult: 'failed');
      expect(r.deliveredOk, isTrue);
      expect(r.robotStranded, isTrue);
      expect(r.resultLabel, '전달 완료 · 로봇 복귀 실패');
      expect(r.failNote, contains('물품은 전달됐습니다'));
    });

    test('배송이 실패한 건은 실패로 센다', () {
      final r = req(
        status: DeliveryStatus.failed,
        deliveryResult: 'failed',
        failCode: 'nav_failed_room',
      );
      expect(r.deliveredOk, isFalse);
      expect(r.resultLabel, '배송 실패');
      expect(r.failNote, contains('병실로 가다 멈췄습니다'));
    });

    test('둘 다 성공하면 그냥 완료다', () {
      final r = req(deliveryResult: 'done', returnResult: 'closed');
      expect(r.deliveredOk, isTrue);
      expect(r.robotStranded, isFalse);
      expect(r.resultLabel, '완료');
      expect(r.failNote, isNull);
    });

    test('취소는 결과값이 있어도 취소로 보인다', () {
      expect(req(status: DeliveryStatus.canceled).resultLabel, '취소됨');
    });
  });

  group('실패 문구', () {
    test('모르는 코드가 와도 화면이 비지 않는다', () {
      // 로봇이 코드표에 없는 값을 보낼 수 있다. 그때 아무 말도 안 하면
      // 간호사는 왜 안 왔는지 알 길이 없다.
      expect(
        DeliveryFail.describe('아직_없는_코드', "'적재' 주행 실패"),
        contains("'적재' 주행 실패"),
      );
      expect(DeliveryFail.describe('', ''), isNotEmpty);
    });

    test('로봇이 적은 내부 문구를 그대로 쓰지 않는다', () {
      // "'적재' 주행 실패" 는 내부 목적지 이름이 새어 나온 말이라,
      // 간호사가 읽어도 무엇을 해야 하는지 알 수 없다.
      final note = DeliveryFail.describe('nav_failed_loading', "'적재' 주행 실패");
      expect(note, isNot(contains('적재')));
      expect(note, contains('널스스테이션'));
    });
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
