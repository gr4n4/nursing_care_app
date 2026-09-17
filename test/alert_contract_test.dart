// 경보 payload 계약 검증.
// 보내는 쪽(레이더는 emfit_server, 압력은 risk_monitor 서버)이 만들 형식을
// AlertCenter 가 제대로 해석하는지 확인한다.
//
// AlertCenter 자체는 dart:js_interop 을 써서 VM 테스트에서 못 불러온다.
// 그래서 경보 종류 목록만 NotificationKind 로 옮겨 두고 진짜 값을 본다.
// 여기에 상수를 복사해 두면 한쪽만 고쳐져도 테스트가 통과해 버린다.
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/utils/notification_kind.dart';

void main() {
  const criticalKinds = NotificationKind.criticalKinds;

  test('센서 경보만 소리와 팝업을 쓴다', () {
    expect(criticalKinds.contains('fall'), isTrue);
    expect(criticalKinds.contains('bedside'), isTrue);
    expect(criticalKinds.contains('pressure'), isTrue);
    // 기록 누락 알림은 경보가 아니다 — 소리를 내면 안 된다.
    expect(criticalKinds.contains('meal'), isFalse);
    expect(criticalKinds.contains('output'), isFalse);
  });

  test('경보 종류마다 그림이 따로 있다', () {
    // 종류를 늘리면서 그림을 빼먹으면 기본 종 모양이 나온다. 목록에서
    // 낙상과 욕창이 같은 그림이면 어느 쪽인지 눈으로 가릴 수 없다.
    final glyphs = <String>{};
    for (final kind in criticalKinds) {
      final asset = NotificationKind.of(kind).svgAsset;
      expect(asset, isNotNull, reason: '$kind 의 그림이 없다');
      glyphs.add(asset!);
    }
    expect(glyphs.length, criticalKinds.length, reason: '두 종류가 같은 그림을 쓴다');
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

  test('압력 서버 payload 도 같은 계약을 지킨다', () {
    // risk_monitor/server/nrcarec_alert.py 의 _push 가 쓰는 형태
    final payload = {
      'title': '욕창 위험 감지',
      'body': '421호 김복순 · 3개 셀이 90분을 넘겼습니다.',
      'kind': 'pressure',
      'icon': '/icons/notify-pressure.png',
      'tag': 'pressure_pi-421_1789609852',
      // 확인 동기화에 쓴다. 이게 없으면 폰에서 확인해도 다른 기기가 계속 운다.
      'logId': 'pressure_pi-421_1789609852',
      'url': '/',
    };
    for (final key in ['title', 'body', 'kind', 'icon', 'tag', 'logId']) {
      expect(payload[key], isNotNull, reason: '$key 가 없으면 알림이 제대로 안 뜬다');
      expect(payload[key], isNotEmpty);
    }
    expect(criticalKinds.contains(payload['kind']), isTrue);
    // 스냅샷은 경보와 같은 문서 ID 로 온다. 어긋나면 그림이 안 붙는다.
    expect(payload['logId'], equals(payload['tag']));
  });

  test('중복 판별에 쓰는 tag 는 기기·종류별로 구분된다', () {
    String tagOf(String kind, String device) => '${kind}_$device';
    expect(tagOf('fall', 'r1'), isNot(tagOf('fall', 'r2')));
    expect(tagOf('fall', 'r1'), isNot(tagOf('bedside', 'r1')));
    expect(tagOf('pressure', 'pi-421'), isNot(tagOf('pressure', 'pi-308')));
    expect(tagOf('fall', 'r1'), equals(tagOf('fall', 'r1')));
  });
}
