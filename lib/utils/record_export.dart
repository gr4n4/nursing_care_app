import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:web/web.dart' as web;

import 'care_date.dart';

/// 하루치 섭취·배설 기록을 엑셀로 내보낸다.
///
/// 메디로에 손으로 옮겨 적어야 해서, 간호과 '섭취·배설 기록지' 양식의 칸 순서를
/// 그대로 따른다. 시트를 둘로 나눈 이유:
///   시트1 '기록지'  = 환자별 하루 합계. 메디로에 그대로 옮겨 적는 용도.
///   시트2 '상세내역' = 무엇을 얼마나 먹고 쌌는지 한 건씩. 값이 이상할 때 근거 확인용.
class RecordExport {
  /// 여러 날짜를 고르면 날짜별로 파일을 하나씩 만들어 zip으로 묶는다.
  /// 한 파일에 여러 날을 몰아넣으면 메디로에 옮길 때 날짜를 골라내야 해서 번거롭다.
  static Future<void> exportDates(List<DateTime> dates) async {
    if (dates.isEmpty) return;

    if (dates.length == 1) {
      final key = careDateKey(dates.first);
      final bytes = await _buildWorkbook(key);
      _download('밸런케어_섭취배설_$key.xlsx', bytes);
      return;
    }

    final archive = Archive();
    for (final d in dates) {
      final key = careDateKey(d);
      final bytes = await _buildWorkbook(key);
      archive.addFile(ArchiveFile('밸런케어_섭취배설_$key.xlsx', bytes.length, bytes));
    }

    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) return;
    final first = careDateKey(dates.first);
    final last = careDateKey(dates.last);
    _download('밸런케어_섭취배설_${first}_$last.zip', zipped);
  }

  // ---------- 엑셀 만들기 ----------

  static Future<List<int>> _buildWorkbook(String dateKey) async {
    final data = await _loadDay(dateKey);

    final excel = Excel.createExcel();
    // 기본으로 생기는 빈 시트 이름을 우리 것으로 바꾸고, 두 번째 시트를 추가한다.
    final formName = '기록지';
    final detailName = '상세내역';
    excel.rename(excel.getDefaultSheet()!, formName);

    _writeFormSheet(excel[formName], dateKey, data);
    _writeDetailSheet(excel[detailName], dateKey, data);

    return excel.encode() ?? <int>[];
  }

  static void _writeFormSheet(
    Sheet sheet,
    String dateKey,
    _DayData data,
  ) {
    // 양식의 2단 머리글(섭취량 / 배설량)을 흉내내되, 표계산에서 다루기 쉽도록
    // 각 열에 온전한 이름을 준다. 병합 머리글은 필터·정렬을 방해한다.
    sheet.appendRow(_text(['섭취·배설 기록지  ·  $dateKey  (하루 기준 오전 7시)']));
    sheet.appendRow(_text([]));
    sheet.appendRow(_text([
      '병실',
      '환자명',
      '섭취-튜브(ml)',
      '섭취-구강(ml)',
      '섭취-수액(ml)',
      '섭취-총량(ml)',
      '배설-자연배뇨(ml)',
      '배설-카테타(ml)',
      '배설-실금(ml)',
      '배설-기저귀(g)',
      '배설-총량(ml)',
      '배변(회)',
      '배변량(g)',
      '밸런스(ml)',
      '부종',
      '배변타입(BSS)',
    ]));

    for (final p in data.patients) {
      sheet.appendRow([
        TextCellValue(p.room),
        TextCellValue(p.name),
        IntCellValue(p.tubeMl),
        IntCellValue(p.oralMl),
        IntCellValue(p.ivMl),
        IntCellValue(p.intakeTotalMl),
        IntCellValue(p.naturalMl),
        IntCellValue(p.catheterMl),
        IntCellValue(p.incontinenceMl),
        IntCellValue(p.diaperGram),
        IntCellValue(p.outputTotalMl),
        IntCellValue(p.stoolCount),
        IntCellValue(p.stoolGram),
        IntCellValue(p.intakeTotalMl - p.outputTotalMl),
        TextCellValue(p.edema > 0 ? '+${p.edema}' : ''),
        TextCellValue(p.stoolType > 0 ? 'Type ${p.stoolType}' : ''),
      ]);
    }
  }

  static void _writeDetailSheet(
    Sheet sheet,
    String dateKey,
    _DayData data,
  ) {
    sheet.appendRow(_text(['상세 내역  ·  $dateKey']));
    sheet.appendRow(_text([]));
    sheet.appendRow(_text([
      '병실',
      '환자명',
      '시간',
      '구분',
      '종류',
      '항목',
      '양',
      '단위',
      '비고',
    ]));

    for (final row in data.details) {
      sheet.appendRow([
        TextCellValue(row.room),
        TextCellValue(row.name),
        TextCellValue(row.time),
        TextCellValue(row.kind),
        TextCellValue(row.category),
        TextCellValue(row.item),
        row.amount == null ? TextCellValue('') : IntCellValue(row.amount!),
        TextCellValue(row.unit),
        TextCellValue(row.note),
      ]);
    }
  }

  static List<CellValue?> _text(List<String> values) =>
      values.map<CellValue?>((v) => TextCellValue(v)).toList();

  // ---------- 데이터 읽기 ----------

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _mealKo(String t) {
    if (t == 'breakfast') return '아침';
    if (t == 'lunch') return '점심';
    if (t == 'dinner') return '저녁';
    return t;
  }

  static String _catKo(String c) {
    switch (c) {
      case 'drink':
        return '음료';
      case 'fruit':
        return '과일';
      case 'tube':
        return '관급식';
      case 'iv':
        return '수액';
      default:
        return c;
    }
  }

  static String _urineKo(String t) {
    switch (t) {
      case 'catheter':
        return '카테타';
      case 'incontinence':
        return '실금';
      case 'diaper':
        return '기저귀';
      default:
        return '자연배뇨';
    }
  }

  static Future<_DayData> _loadDay(String dateKey) async {
    final db = FirebaseFirestore.instance;

    final results = await Future.wait([
      db.collection('patients').get(),
      db.collection('meal_records').where('date', isEqualTo: dateKey).get(),
      db.collection('water_records').where('date', isEqualTo: dateKey).get(),
      db.collection('output_records').where('date', isEqualTo: dateKey).get(),
      db.collection('daily_assessments').where('date', isEqualTo: dateKey).get(),
    ]);

    final assessByPatient = <String, Map<String, dynamic>>{};
    for (final d in results[4].docs) {
      final data = d.data();
      final pid = (data['patientId'] ?? '').toString();
      if (pid.isNotEmpty) assessByPatient[pid] = data;
    }

    final patients = <_PatientRow>[];
    final details = <_DetailRow>[];

    for (final doc in results[0].docs) {
      final patient = doc.data();
      // 숨긴 환자는 대시보드에서도 아래로 빠지므로 내보내기에서도 제외한다.
      if (patient['isActive'] == false) continue;

      final pid = doc.id;
      final name = (patient['name'] ?? '').toString();
      final room = (patient['room'] ?? '').toString().replaceAll('호', '').trim();

      var tubeMl = 0, oralMl = 0, ivMl = 0;
      var naturalMl = 0, catheterMl = 0, incontinenceMl = 0;
      var diaperGram = 0, urineMl = 0, stoolGram = 0, stoolCount = 0;

      for (final m in results[1].docs) {
        final d = m.data();
        if (d['patientId'] != pid) continue;

        final fluid = _toInt(d['totalFluidMl']);
        oralMl += fluid;

        details.add(_DetailRow(
          room: room,
          name: name,
          time: (d['time'] ?? '').toString(),
          kind: '섭취',
          category: '식사',
          item: _mealKo((d['mealType'] ?? '').toString()),
          amount: fluid,
          unit: 'ml',
          note: '식사 ${_toInt(d['totalFoodGram'])}g',
        ));
      }

      for (final w in results[2].docs) {
        final d = w.data();
        if (d['patientId'] != pid) continue;

        final ml = _toInt(d['amountMl']);
        final cat = (d['category'] ?? 'drink').toString();
        if (cat == 'tube') {
          tubeMl += ml;
        } else if (cat == 'iv') {
          ivMl += ml;
        } else {
          oralMl += ml;
        }

        details.add(_DetailRow(
          room: room,
          name: name,
          time: (d['time'] ?? '').toString(),
          kind: '섭취',
          category: _catKo(cat),
          item: (d['name'] ?? '').toString(),
          amount: ml,
          unit: 'ml',
          note: '',
        ));
      }

      for (final o in results[3].docs) {
        final d = o.data();
        if (d['patientId'] != pid) continue;

        final amount = _toInt(d['urineAmount']);
        final type = (d['urineType'] ?? 'natural').toString();
        final isDiaper = type == 'diaper' || (d['urineUnit'] ?? '') == 'g';

        if (isDiaper) {
          diaperGram += amount;
        } else {
          urineMl += amount;
          if (type == 'catheter') {
            catheterMl += amount;
          } else if (type == 'incontinence') {
            incontinenceMl += amount;
          } else {
            naturalMl += amount;
          }
        }

        final hasStool = d['stoolYn'] == true;
        if (hasStool) {
          stoolGram += _toInt(d['stoolAmount']);
          stoolCount += _toInt(d['stoolCount']);
        }

        details.add(_DetailRow(
          room: room,
          name: name,
          time: (d['time'] ?? '').toString(),
          kind: '배설',
          category: _urineKo(type),
          item: '',
          amount: amount,
          unit: isDiaper ? 'g' : 'ml',
          note: hasStool ? '배변 ${_toInt(d['stoolAmount'])}g' : '',
        ));
      }

      final assess = assessByPatient[pid];

      patients.add(_PatientRow(
        room: room,
        name: name,
        tubeMl: tubeMl,
        oralMl: oralMl,
        ivMl: ivMl,
        intakeTotalMl: tubeMl + oralMl + ivMl,
        naturalMl: naturalMl,
        catheterMl: catheterMl,
        incontinenceMl: incontinenceMl,
        diaperGram: diaperGram,
        // 기저귀는 g로 재지만 1g≈1ml로 보고 합산한다(대시보드와 동일 규칙).
        outputTotalMl: urineMl + diaperGram,
        stoolCount: stoolCount,
        stoolGram: stoolGram,
        edema: _toInt(assess?['edemaGrade']),
        stoolType: _toInt(assess?['stoolType']),
      ));
    }

    int roomNo(String r) => int.tryParse(r) ?? 999999;
    patients.sort((a, b) {
      final c = roomNo(a.room).compareTo(roomNo(b.room));
      return c != 0 ? c : a.name.compareTo(b.name);
    });

    details.sort((a, b) {
      final c = roomNo(a.room).compareTo(roomNo(b.room));
      if (c != 0) return c;
      final n = a.name.compareTo(b.name);
      if (n != 0) return n;
      return a.time.compareTo(b.time);
    });

    return _DayData(patients: patients, details: details);
  }

  // ---------- 브라우저 다운로드 ----------

  /// 만든 바이트를 파일로 내려받게 한다.
  /// data: URL 대신 Blob을 쓰는 이유 — 수 MB짜리 파일에서 URL 길이 제한에 걸린다.
  static void _download(String filename, List<int> bytes) {
    final blob = web.Blob(
      [Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(
        type: 'application/octet-stream',
      ),
    );

    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename;

    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // 즉시 해제하면 일부 브라우저에서 다운로드가 취소되므로 잠시 뒤에 정리한다.
    Future<void>.delayed(const Duration(seconds: 10), () {
      web.URL.revokeObjectURL(url);
    });
  }
}

class _DayData {
  final List<_PatientRow> patients;
  final List<_DetailRow> details;

  _DayData({required this.patients, required this.details});
}

class _PatientRow {
  final String room;
  final String name;
  final int tubeMl;
  final int oralMl;
  final int ivMl;
  final int intakeTotalMl;
  final int naturalMl;
  final int catheterMl;
  final int incontinenceMl;
  final int diaperGram;
  final int outputTotalMl;
  final int stoolCount;
  final int stoolGram;
  final int edema;
  final int stoolType;

  _PatientRow({
    required this.room,
    required this.name,
    required this.tubeMl,
    required this.oralMl,
    required this.ivMl,
    required this.intakeTotalMl,
    required this.naturalMl,
    required this.catheterMl,
    required this.incontinenceMl,
    required this.diaperGram,
    required this.outputTotalMl,
    required this.stoolCount,
    required this.stoolGram,
    required this.edema,
    required this.stoolType,
  });
}

class _DetailRow {
  final String room;
  final String name;
  final String time;
  final String kind;
  final String category;
  final String item;
  final int? amount;
  final String unit;
  final String note;

  _DetailRow({
    required this.room,
    required this.name,
    required this.time,
    required this.kind,
    required this.category,
    required this.item,
    required this.amount,
    required this.unit,
    required this.note,
  });
}
