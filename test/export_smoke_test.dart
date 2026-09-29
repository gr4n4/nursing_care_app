import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/utils/care_date.dart';

/// 엑셀 4시트 생성이 실제로 동작하는지 확인한다.
/// 브라우저에서 열어보기 전에 라이브러리 사용법이 맞는지 먼저 잡기 위함.
void main() {
  test('시트 4개짜리 엑셀이 바이트로 인코딩된다', () {
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

    // 시트 이름에 가운뎃점이 들어간다. 엑셀이 시트명에 못 쓰는 글자
    // (: \ / ? * [ ])가 아닌지, 31자를 넘지 않는지 여기서 걸린다.
    excel['욕창 위험'].appendRow([
      TextCellValue('시간'),
      TextCellValue('대상'),
      TextCellValue('위험 셀'),
    ]);
    excel['욕창 위험'].appendRow([
      TextCellValue('16:00'),
      TextCellValue('421호 김복순'),
      IntCellValue(3),
    ]);

    excel['낙상·걸터앉음'].appendRow([
      TextCellValue('시간'),
      TextCellValue('종류'),
      TextCellValue('병실'),
    ]);
    excel['낙상·걸터앉음'].appendRow([
      TextCellValue('14:32'),
      TextCellValue('낙상'),
      TextCellValue('421'),
    ]);

    final bytes = excel.encode();

    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(500), reason: 'xlsx 내용이 비어 있으면 안 된다');
    // xlsx 는 zip 컨테이너라 PK 시그니처로 시작한다.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);
    expect(
      excel.sheets.keys,
      containsAll(['기록지', '상세내역', '욕창 위험', '낙상·걸터앉음']),
    );
    for (final name in excel.sheets.keys) {
      expect(name.length, lessThanOrEqualTo(31),
          reason: '엑셀 시트 이름은 31자를 넘을 수 없다');
      expect(RegExp(r'[:\/?*\[\]]').hasMatch(name), isFalse,
          reason: '엑셀 시트 이름에 못 쓰는 글자가 있다: $name');
    }
  });

  test('간호일 구간은 07시에 시작해 다음날 07시에 끝난다', () {
    // 경보는 date 필드가 없어 이 구간으로 걸러 내보낸다. 경계가 어긋나면
    // 새벽 경보가 엉뚱한 날짜 파일에 들어간다.
    final start = careDayStart('2026-09-29');
    final end = careDayEnd('2026-09-29');

    expect(start, DateTime(2026, 9, 29, 7));
    expect(end, DateTime(2026, 9, 30, 7));

    // 새벽 3시 경보는 전날(9/29) 간호일에 속한다.
    final dawn = DateTime(2026, 9, 30, 3);
    expect(dawn.isAfter(start) && dawn.isBefore(end), isTrue);
    expect(careDateKey(dawn), '2026-09-29');
  });
}
