import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web/web.dart' as web;

import 'care_date.dart';
import 'xlsx.dart';

/// 하루치 섭취·배설 기록을 엑셀로 내보낸다.
///
/// 메디로에 손으로 옮겨 적어야 해서, 간호과 '섭취·배설 기록지' 양식의 칸 순서를
/// 그대로 따른다. 시트를 둘로 나눈 이유:
///   시트1 '기록지'  = 환자별 하루 합계. 메디로에 그대로 옮겨 적는 용도.
///   시트2 '상세내역' = 무엇을 얼마나 먹고 쌌는지 한 건씩. 값이 이상할 때 근거 확인용.
///   시트3 '욕창 위험'  = 압력 센서 경보. 어디가 눌렸고 누가 확인했는지.
///   시트4 '낙상·걸터앉음' = 레이더 경보.
///
/// 경보를 같이 넣는 이유: 그날 무슨 일이 있었는지 묻는 자리에서 섭취·배설만
/// 들고 가면 "그날 낙상 있었죠?"에 답할 수 없다. 한 파일에 있어야 한다.
class RecordExport {
  /// 여러 날짜를 고르면 날짜별로 파일을 하나씩 만들어 zip으로 묶는다.
  /// 한 파일에 여러 날을 몰아넣으면 메디로에 옮길 때 날짜를 골라내야 해서 번거롭다.
  static Future<void> exportDates(List<DateTime> dates) async {
    if (dates.isEmpty) return;

    if (dates.length == 1) {
      final key = careDateKeyOfDay(dates.first);
      final bytes = await _buildWorkbook(key);
      _download('NRCarec_섭취배설_$key.xlsx', bytes);
      return;
    }

    final archive = Archive();
    for (final d in dates) {
      final key = careDateKeyOfDay(d);
      final bytes = await _buildWorkbook(key);
      archive.addFile(ArchiveFile('NRCarec_섭취배설_$key.xlsx', bytes.length, bytes));
    }

    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) return;
    final first = careDateKeyOfDay(dates.first);
    final last = careDateKeyOfDay(dates.last);
    _download('NRCarec_섭취배설_${first}_$last.zip', zipped);
  }

  // ---------- 엑셀 만들기 ----------

  static Future<List<int>> _buildWorkbook(String dateKey) async {
    final data = await _loadDay(dateKey);

    final book = XlsxWorkbook();
    _writeFormSheet(book.addSheet('기록지'), dateKey, data);
    _writeDetailSheet(book.addSheet('상세내역'), dateKey, data);
    _writePressureSheet(book.addSheet('욕창 위험'), dateKey, data);
    _writeAlertSheet(book.addSheet('낙상·걸터앉음'), dateKey, data);
    return book.encode();
  }

  static void _writeFormSheet(
    XlsxSheet sheet,
    String dateKey,
    _DayData data,
  ) {
    // 양식의 2단 머리글(섭취량 / 배설량)을 흉내내되, 표계산에서 다루기 쉽도록
    // 각 열에 온전한 이름을 준다. 병합 머리글은 필터·정렬을 방해한다.
    sheet.addTextRow((['섭취·배설 기록지  ·  $dateKey  (하루 기준 오전 7시)']));
    sheet.addTextRow(([]));
    sheet.addTextRow(([
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
      sheet.addRow([
        XlsxCell.text(p.room),
        XlsxCell.text(p.name),
        XlsxCell.number(p.tubeMl),
        XlsxCell.number(p.oralMl),
        XlsxCell.number(p.ivMl),
        XlsxCell.number(p.intakeTotalMl),
        XlsxCell.number(p.naturalMl),
        XlsxCell.number(p.catheterMl),
        XlsxCell.number(p.incontinenceMl),
        XlsxCell.number(p.diaperGram),
        XlsxCell.number(p.outputTotalMl),
        XlsxCell.number(p.stoolCount),
        XlsxCell.number(p.stoolGram),
        XlsxCell.number(p.intakeTotalMl - p.outputTotalMl),
        XlsxCell.text(p.edema > 0 ? '+${p.edema}' : ''),
        XlsxCell.text(p.stoolType > 0 ? 'Type ${p.stoolType}' : ''),
      ]);
    }
  }

  static void _writeDetailSheet(
    XlsxSheet sheet,
    String dateKey,
    _DayData data,
  ) {
    sheet.addTextRow((['상세 내역  ·  $dateKey']));
    sheet.addTextRow(([]));
    sheet.addTextRow(([
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
      sheet.addRow([
        XlsxCell.text(row.room),
        XlsxCell.text(row.name),
        XlsxCell.text(row.time),
        XlsxCell.text(row.kind),
        XlsxCell.text(row.category),
        XlsxCell.text(row.item),
        row.amount == null ? XlsxCell.text('') : XlsxCell.number(row.amount!),
        XlsxCell.text(row.unit),
        XlsxCell.text(row.note),
      ]);
    }
  }

  /// 시트3 — 압력 센서가 올린 욕창 위험 경보.
  ///
  /// 부위와 확인자를 같이 싣는다. 경보가 났다는 것만으로는 기록이 되지 않고,
  /// "어디였고 누가 갔는지"가 있어야 나중에 되짚을 수 있다.
  static void _writePressureSheet(
    XlsxSheet sheet,
    String dateKey,
    _DayData data,
  ) {
    sheet.addTextRow((['욕창 위험 경보  ·  $dateKey']));
    sheet.addTextRow(([]));
    sheet.addTextRow((
        ['시간', '대상', '위험 셀', '부위', '확인자', '확인 시각']));

    if (data.pressureAlerts.isEmpty) {
      sheet.addTextRow((['(이 날 욕창 경보 없음)']));
      return;
    }

    for (final a in data.pressureAlerts) {
      sheet.addRow([
        XlsxCell.text(a.time),
        XlsxCell.text(a.who),
        a.cells == null ? XlsxCell.text('') : XlsxCell.number(a.cells!),
        XlsxCell.text(a.site),
        XlsxCell.text(a.ackBy),
        XlsxCell.text(a.ackTime),
      ]);
    }
  }

  /// 시트4 — 레이더가 올린 낙상·걸터앉음 경보.
  static void _writeAlertSheet(
    XlsxSheet sheet,
    String dateKey,
    _DayData data,
  ) {
    sheet.addTextRow((['낙상·걸터앉음 경보  ·  $dateKey']));
    sheet.addTextRow(([]));
    sheet.addTextRow((
        ['시간', '종류', '병실', '환자명', '확인자', '확인 시각']));

    if (data.sensorAlerts.isEmpty) {
      sheet.addTextRow((['(이 날 낙상·걸터앉음 경보 없음)']));
      return;
    }

    for (final a in data.sensorAlerts) {
      sheet.addRow([
        XlsxCell.text(a.time),
        XlsxCell.text(a.kindKo),
        XlsxCell.text(a.room),
        XlsxCell.text(a.name),
        XlsxCell.text(a.ackBy),
        XlsxCell.text(a.ackTime),
      ]);
    }
  }

  // ---------- 데이터 읽기 ----------

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// 앱에서 고른 그대로 적는다(0 · 1/4 · 1/3 · 1/2 · 전체).
  /// 0.33 같은 숫자로 적으면 간호사가 무엇을 눌렀는지 알아보기 어렵다.
  static String _ratioKo(double r) {
    if (r >= 0.999) return '전체';
    if ((r - 0.5).abs() < 0.01) return '1/2';
    if ((r - 0.33).abs() < 0.02) return '1/3';
    if ((r - 0.25).abs() < 0.01) return '1/4';
    return '${(r * 100).round()}%';
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
      // 알림 기록에는 date 필드가 없고 발송 시각(sentAt)뿐이라 구간으로 찾는다.
      // 한 필드 범위 조건이라 복합 색인이 필요 없다.
      db
          .collection('notification_log')
          .where('sentAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(careDayStart(dateKey)))
          .where('sentAt', isLessThan: Timestamp.fromDate(careDayEnd(dateKey)))
          .orderBy('sentAt')
          .get(),
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

        // 한 끼를 한 줄로 합치면 "밥을 얼마나 먹어서 수분이 얼마"인지 알 수
        // 없다. 상세내역은 값이 이상할 때 근거를 보는 곳이므로 주식·국·반찬을
        // 따로 편다. 안 먹은 칸(비율 0, 종류 '없음')은 넣지 않는다.
        final meal = _mealKo((d['mealType'] ?? '').toString());
        final time = (d['time'] ?? '').toString();

        void part(String item, dynamic ratio, dynamic gram, dynamic waterMl) {
          final r = _toDouble(ratio);
          if (r <= 0) return;
          final g = _toInt(gram);
          details.add(_DetailRow(
            room: room,
            name: name,
            time: time,
            kind: '섭취',
            category: meal,
            item: item,
            amount: _toInt(waterMl),
            unit: 'ml',
            note: g > 0 ? '${_ratioKo(r)} · ${g}g' : _ratioKo(r),
          ));
        }

        final staple = (d['stapleType'] ?? '').toString();
        part(staple.isEmpty ? '주식' : '주식 $staple', d['stapleRatio'],
            d['stapleGram'], d['stapleWaterMl']);
        part('국', d['soupRatio'], d['soupServingGram'], d['soupWaterMl']);
        for (var i = 1; i <= 4; i++) {
          final type = (d['side${i}Type'] ?? '').toString();
          if (type.isEmpty || type == '없음') continue;
          part('반찬 $type', d['side${i}Ratio'], d['side${i}Gram'],
              d['side${i}WaterMl']);
        }
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

    final pressureAlerts = <_PressureAlertRow>[];
    final sensorAlerts = <_SensorAlertRow>[];

    for (final doc in results[5].docs) {
      final a = doc.data();
      final kind = (a['kind'] ?? '').toString();
      if (kind != 'pressure' && kind != 'fall' && kind != 'bedside') continue;

      final sent = a['sentAt'];
      final time = sent is Timestamp ? wallClockTime(sent.toDate()) : '';
      final ackAt = a['ackedAt'];
      final ackTime = ackAt is Timestamp ? wallClockTime(ackAt.toDate()) : '';
      final ackName = (a['ackedByName'] ?? '').toString().trim();
      final ackBy = ackName.isNotEmpty
          ? ackName
          : (a['ackedBy'] ?? '').toString().split('@').first;

      if (kind == 'pressure') {
        // 부위는 따로 적히므로(양쪽에서 적을 수 있다) 문서를 하나 더 읽는다.
        // 하루에 몇 건뿐이라 읽기 비용이 문제되지 않는다.
        var site = '';
        try {
          final s = await db.collection('pressure_sites').doc(doc.id).get();
          site = (s.data()?['site'] ?? '').toString().trim();
        } catch (_) {
          // 부위를 못 읽어도 경보 자체는 내보낸다.
        }
        pressureAlerts.add(_PressureAlertRow(
          time: time,
          who: (a['room'] ?? '').toString(),
          cells: a['cellCount'] is int ? a['cellCount'] as int : null,
          site: site,
          ackBy: ackBy,
          ackTime: ackTime,
        ));
      } else {
        sensorAlerts.add(_SensorAlertRow(
          time: time,
          kindKo: kind == 'fall' ? '낙상' : '걸터앉음',
          room: (a['room'] ?? '').toString(),
          name: (a['patientName'] ?? '').toString(),
          ackBy: ackBy,
          ackTime: ackTime,
        ));
      }
    }

    return _DayData(
      patients: patients,
      details: details,
      pressureAlerts: pressureAlerts,
      sensorAlerts: sensorAlerts,
    );
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
  final List<_PressureAlertRow> pressureAlerts;
  final List<_SensorAlertRow> sensorAlerts;

  _DayData({
    required this.patients,
    required this.details,
    this.pressureAlerts = const [],
    this.sensorAlerts = const [],
  });
}

class _PressureAlertRow {
  final String time;

  /// 센서에 지어 준 이름(예: '421호 김복순'). 압력 쪽은 환자를 모른다.
  final String who;
  final int? cells;
  final String site;
  final String ackBy;
  final String ackTime;

  _PressureAlertRow({
    required this.time,
    required this.who,
    required this.cells,
    required this.site,
    required this.ackBy,
    required this.ackTime,
  });
}

class _SensorAlertRow {
  final String time;
  final String kindKo;
  final String room;
  final String name;
  final String ackBy;
  final String ackTime;

  _SensorAlertRow({
    required this.time,
    required this.kindKo,
    required this.room,
    required this.name,
    required this.ackBy,
    required this.ackTime,
  });
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
