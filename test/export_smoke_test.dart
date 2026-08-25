import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// 엑셀 2시트 생성이 실제로 동작하는지 확인한다.
/// 브라우저에서 열어보기 전에 라이브러리 사용법이 맞는지 먼저 잡기 위함.
void main() {
  test('시트 2개짜리 엑셀이 바이트로 인코딩된다', () {
    final excel = Excel.createExcel();
    excel.rename(excel.getDefaultSheet()!, '기록지');

    excel['기록지'].appendRow([
      TextCellValue('병실'),
      TextCellValue('환자명'),
      TextCellValue('섭취-튜브(ml)'),
    ]);
    excel['기록지'].appendRow([
      TextCellValue('401'),
      TextCellValue('홍길동'),
      IntCellValue(400),
    ]);

    excel['상세내역'].appendRow([
      TextCellValue('병실'),
      TextCellValue('시간'),
      TextCellValue('구분'),
    ]);
    excel['상세내역'].appendRow([
      TextCellValue('401'),
      TextCellValue('08:10'),
      TextCellValue('섭취'),
    ]);

    final bytes = excel.encode();

    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(500), reason: 'xlsx 내용이 비어 있으면 안 된다');
    // xlsx 는 zip 컨테이너라 PK 시그니처로 시작한다.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
    expect(excel.sheets.keys, containsAll(['기록지', '상세내역']));
  });
}
