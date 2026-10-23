import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nursing_care_app/utils/care_date.dart';
import 'package:nursing_care_app/utils/xlsx.dart';

/// xlsx 를 직접 만드는 부분이 실제로 열리는 파일을 뱉는지 확인한다.
///
/// excel 패키지를 걷어낸 이유는 xlsx.dart 의 주석에 있다 — 그쪽은 새 파일을
/// 만들 때 템플릿을 풀어야 해서 wasm 빌드에서 죽었다.
void main() {
  group('달력에서 고른 날짜는 빼지 않는다', () {
    // 두 번 틀린 자리다. v2.3.2 에서 자료를 찾는 쪽을 고쳤는데, 화면에
    // 적는 글자는 그대로 둬서 "21일을 골랐는데 20일로 보인다" 가 됐다.
    //
    // careDateKey/careDateDisplay 는 '이 **시각**이 어느 간호일인가' 를
    // 가리는 함수라 7시간을 뺀다. 달력이 주는 자정에서 빼면 전날이 된다.
    final picked = DateTime(2026, 10, 21);

    test('키로 만들 때', () {
      expect(careDateKeyOfDay(picked), '2026-10-21');
      expect(careDateKey(picked), '2026-10-20'); // 이것을 쓰면 안 된다
    });

    test('화면에 적을 때', () {
      expect(careKeyDisplay(careDateKeyOfDay(picked)), '2026.10.21 (수)');
      expect(careDateDisplay(picked), '2026.10.20'); // 이것을 쓰면 안 된다
    });

    test('실제 시각에는 careDateKey 가 맞다', () {
      // 새벽 3시 기록은 그 밤을 지킨 사람의 하루에 들어가야 한다.
      expect(careDateKey(DateTime(2026, 10, 21, 3, 0)), '2026-10-20');
      expect(careDateKey(DateTime(2026, 10, 21, 8, 0)), '2026-10-21');
    });
  });

  group('간호일 앞뒤로 옮기기', () {
    test('하루씩 옮긴다', () {
      expect(careKeyShift('2026-10-23', -1), '2026-10-22');
      expect(careKeyShift('2026-10-23', 1), '2026-10-24');
    });

    test('달과 해를 넘긴다', () {
      expect(careKeyShift('2026-03-01', -1), '2026-02-28');
      expect(careKeyShift('2026-01-01', -1), '2025-12-31');
      expect(careKeyShift('2026-12-31', 1), '2027-01-01');
    });

    test('옮겨도 간호일 구간이 따라온다', () {
      // 화면에서 하루 뒤로 가면 자료를 찾는 구간도 같이 하루 뒤여야 한다.
      final a = careDayStart(careKeyShift('2026-10-23', -1));
      expect(a, DateTime(2026, 10, 22, 7));
      expect(careDayEnd(careKeyShift('2026-10-23', -1)),
          DateTime(2026, 10, 23, 7));
    });

    test('화면 글자에 요일이 붙는다', () {
      // 2026-10-23 은 금요일.
      expect(careKeyDisplay('2026-10-23'), '2026.10.23 (금)');
    });
  });

  group('달력 하루로 다시 묶기', () {
    // 기록은 간호일(date)과 벽시계 시각(time)을 같이 들고 있다. 그래서
    // 질의를 새로 짜지 않고 다시 묶을 수 있다.
    //
    //   달력 10/23 = (간호일 10/22 중 07:00 이전) + (간호일 10/23 중 07:00 이후)
    bool beforeSeven(String t) => t.length >= 5 && t.compareTo('07:00') < 0;

    test('07시가 경계다', () {
      expect(beforeSeven('06:59'), isTrue);
      expect(beforeSeven('07:00'), isFalse);
      expect(beforeSeven('00:00'), isTrue);
      expect(beforeSeven('23:59'), isFalse);
    });

    test('시각이 없으면 전날로 넘기지 않는다', () {
      // 없는 것을 전날로 떠넘기면 그날 자료에서 조용히 사라진다.
      expect(beforeSeven(''), isFalse);
      expect(beforeSeven('7'), isFalse);
    });

    test('앞 간호일 키는 하루를 뺀다', () {
      String prev(String k) {
        final d = DateTime.parse(k).subtract(const Duration(days: 1));
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      expect(prev('2026-10-23'), '2026-10-22');
      expect(prev('2026-01-01'), '2025-12-31');  // 해 넘김
      expect(prev('2026-03-01'), '2026-02-28');  // 달 넘김
    });
  });

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

  test('달력에서 고른 날짜는 빼지 않고 그대로 키가 된다', () {
    // 달력은 자정을 준다. careDateKey 로 넘기면 7시간을 빼서 전날이 되고,
    // 9월 30일을 골라도 9월 29일 자료를 찾아 전부 0 으로 나온다.
    final picked = DateTime(2026, 9, 30);
    expect(careDateKeyOfDay(picked), '2026-09-30');
    expect(careDateKey(picked), '2026-09-29', reason: '이래서 그대로 쓰면 안 된다');

    // 실제 시각을 넘기는 쪽(기록 입력 화면 등)은 지금처럼 careDateKey 가 맞다.
    expect(careDateKey(DateTime(2026, 9, 30, 14, 19)), '2026-09-30');
    expect(careDateKey(DateTime(2026, 9, 30, 3, 0)), '2026-09-29');
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
