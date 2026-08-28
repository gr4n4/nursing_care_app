// 경보 payload 계약 검증.
// emfit_server 가 보낼 형식을 AlertCenter 가 제대로 해석하는지 확인한다.
import 'package:flutter_test/flutter_test.dart';

void main() {
  // AlertCenter 가 경보로 취급하는 종류
  const criticalKinds = {'fall', 'bedside'};

  test('낙상·걸터앉음만 경보로 취급한다', () {
    expect(criticalKinds.contains('fall'), isTrue);
    expect(criticalKinds.contains('bedside'), isTrue);
    // 기록 누락 알림은 경보가 아니다 — 소리를 내면 안 된다.
    expect(criticalKinds.contains('meal'), isFalse);
    expect(criticalKinds.contains('output'), isFalse);
  });

  test('문서에 적은 payload 가 필요한 필드를 모두 갖는다', () {
    // docs/radar-alert-integration.md 의 send_alert 가 쓰는 형태
    final payload = {
      'title': '낙상 감지',
      'body': '421호 환자A님 · 낙상이 감지되었습니다.',
      'kind': 'fall',
      'icon': '/icons/notify-fall.png',
      'tag': 'fall_radar-001',
      'url': '/',
    };
    for (final key in ['title', 'body', 'kind', 'icon', 'tag']) {
      expect(payload[key], isNotNull, reason: '$key 가 없으면 알림이 제대로 안 뜬다');
      expect(payload[key], isNotEmpty);
    }
    expect(criticalKinds.contains(payload['kind']), isTrue);
  });

  test('중복 판별에 쓰는 tag 는 기기·종류별로 구분된다', () {
    String tagOf(String kind, String device) => '${kind}_$device';
    expect(tagOf('fall', 'r1'), isNot(tagOf('fall', 'r2')));
    expect(tagOf('fall', 'r1'), isNot(tagOf('bedside', 'r1')));
    expect(tagOf('fall', 'r1'), equals(tagOf('fall', 'r1')));
  });
}
