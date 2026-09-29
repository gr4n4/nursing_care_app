import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/utils/care_date.dart';
import 'package:nursing_care_app/utils/xlsx.dart';

/// xlsx 를 직접 만드는 부분이 실제로 열리는 파일을 뱉는지 확인한다.
///
/// excel 패키지를 걷어낸 이유는 xlsx.dart 의 주석에 있다 — 그쪽은 새 파일을
/// 만들 때 템플릿을 풀어야 해서 wasm 빌드에서 죽었다.
void main() {
  test('시트 4개짜리 xlsx 가 zip 으로 인코딩된다', () {
    final book = XlsxWorkbook();

    final form = book.addSheet('기록지');
    form.addTextRow(['병실', '환자명', '섭취-튜브(ml)']);
    form.addRow([
      XlsxCell.text('401'),
      XlsxCell.text('홍길동'),
      XlsxCell.number(400),
    ]);

    book.addSheet('상세내역').addTextRow(['병실', '시간', '구분']);
    book.addSheet('욕창 위험').addTextRow(['시간', '대상', '위험 셀']);
    book.addSheet('낙상·걸터앉음').addTextRow(['시간', '종류', '병실']);

    final bytes = book.encode();

    expect(bytes.length, greaterThan(500), reason: 'xlsx 내용이 비어 있으면 안 된다');
    // xlsx 는 zip 컨테이너라 PK 시그니처로 시작한다.
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);

    // 파이썬으로 열어 볼 수 있게 남긴다(테스트 자체는 이 파일을 안 본다).
    final out = Platform.environment['XLSX_OUT'];
    if (out != null && out.isNotEmpty) {
      File(out).writeAsBytesSync(bytes);
    }
  });

  test('엑셀이 거부하는 시트 이름을 미리 손본다', () {
    final book = XlsxWorkbook();
    // : \ / ? * [ ] 는 엑셀이 시트 이름에 못 쓰게 한다. 그대로 두면 파일은
    // 만들어지는데 열 때 "복구가 필요합니다" 가 뜬다.
    expect(book.addSheet('기록/지: 8월').name, '기록 지  8월');
    expect(book.addSheet('가' * 40).name.length, 31);
  });

  test('칸 이름은 A, Z 다음 AA 로 넘어간다', () {
    expect(XlsxWorkbook.columnName(0), 'A');
    expect(XlsxWorkbook.columnName(25), 'Z');
    expect(XlsxWorkbook.columnName(26), 'AA');
    expect(XlsxWorkbook.columnName(27), 'AB');
    expect(XlsxWorkbook.columnName(51), 'AZ');
    expect(XlsxWorkbook.columnName(52), 'BA');
  });

  test('간호일 구간은 07시에 시작해 다음날 07시에 끝난다', () {
    // 경보는 date 필드가 없어 이 구간으로 걸러 내보낸다. 경계가 어긋나면
    // 새벽 경보가 엉뚱한 날짜 파일에 들어간다.
    expect(careDayStart('2026-09-29'), DateTime(2026, 9, 29, 7));
    expect(careDayEnd('2026-09-29'), DateTime(2026, 9, 30, 7));

    final dawn = DateTime(2026, 9, 30, 3);
    expect(careDateKey(dawn), '2026-09-29');
  });
}
