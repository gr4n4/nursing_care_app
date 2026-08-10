// 기본 스모크 테스트 자리표시자.
// 앱 위젯(CareNoteApp)은 Firebase 초기화가 필요해 여기서 직접 띄우지 않는다.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanity', () {
    expect(1 + 1, 2);
  });
}
