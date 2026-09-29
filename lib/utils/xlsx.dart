import 'dart:convert';

import 'package:archive/archive.dart';

/// xlsx 파일을 직접 만든다.
///
/// excel 패키지를 쓰지 않는 이유: 그쪽은 새 파일을 만들 때 패키지에 박아 둔
/// 템플릿 xlsx 를 **풀어서** 읽는데, 그 압축 해제가 wasm 빌드에서 죽는다.
/// archive 3.6.1 의 inflateBuffer 가 dart.library.io / dart.library.js 로만
/// 갈라져 있어서다 — wasm 에는 둘 다 없어 stub 으로 떨어지고
/// "inflateBuffer requires html or io" 를 던진다.
///
/// 정작 그 갈래들이 하는 일은 순수 Dart 구현을 부르는 것뿐이라 wasm 에서도
/// 돌 수 있는 코드인데, 조건문에 wasm 갈래가 빠진 포장 실수다.
///
/// 우리는 만들기만 하면 되고 만들기(zip 압축)는 순수 Dart 라 wasm 에서 돈다.
/// 그래서 푸는 일이 아예 없는 쪽으로 간다. 서식 없이 글자와 정수만 담는,
/// 우리가 쓰는 만큼의 xlsx 다.
class XlsxSheet {
  /// 엑셀 시트 이름 제한: 31자 이하, : \ / ? * [ ] 못 씀.
  final String name;
  final List<List<XlsxCell?>> rows = [];

  XlsxSheet(this.name);

  void addRow(List<XlsxCell?> cells) => rows.add(cells);

  /// 글자만 있는 줄을 간단히 넣을 때.
  void addTextRow(List<String> values) =>
      rows.add(values.map<XlsxCell?>(XlsxCell.text).toList());
}

class XlsxCell {
  final String? _text;
  final int? _number;

  const XlsxCell._(this._text, this._number);

  factory XlsxCell.text(String v) => XlsxCell._(v, null);
  factory XlsxCell.number(int v) => XlsxCell._(null, v);

  bool get isEmpty => _number == null && (_text == null || _text.isEmpty);
}

class XlsxWorkbook {
  final List<XlsxSheet> sheets = [];

  XlsxSheet addSheet(String name) {
    final sheet = XlsxSheet(_safeName(name));
    sheets.add(sheet);
    return sheet;
  }

  /// 엑셀이 거부하는 시트 이름을 미리 손본다. 여기서 안 걸러내면 파일은
  /// 만들어지는데 엑셀이 "복구가 필요합니다" 를 띄운다.
  static String _safeName(String name) {
    var s = name.replaceAll(RegExp(r'[:\/?*\[\]]'), ' ').trim();
    if (s.isEmpty) s = 'Sheet';
    return s.length <= 31 ? s : s.substring(0, 31);
  }

  List<int> encode() {
    final archive = Archive();
    void add(String path, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels());
    add('xl/workbook.xml', _workbook());
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
    }

    return ZipEncoder().encode(archive) ?? <int>[];
  }

  // ---------- 조각들 ----------

  String _contentTypes() {
    final overrides = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      overrides.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml"'
          ' ContentType="application/vnd.openxmlformats-officedocument'
          '.spreadsheetml.worksheet+xml"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels"'
        ' ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml"'
        ' ContentType="application/vnd.openxmlformats-officedocument'
        '.spreadsheetml.sheet.main+xml"/>'
        '$overrides</Types>';
  }

  String _rootRels() =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1"'
      ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"'
      ' Target="xl/workbook.xml"/></Relationships>';

  String _workbook() {
    final list = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      list.write('<sheet name="${_esc(sheets[i].name)}"'
          ' sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
        ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>$list</sheets></workbook>';
  }

  String _workbookRels() {
    final list = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      list.write('<Relationship Id="rId${i + 1}"'
          ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"'
          ' Target="worksheets/sheet${i + 1}.xml"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$list</Relationships>';
  }

  String _sheetXml(XlsxSheet sheet) {
    final data = StringBuffer();
    for (var r = 0; r < sheet.rows.length; r++) {
      final cells = sheet.rows[r];
      data.write('<row r="${r + 1}">');
      for (var c = 0; c < cells.length; c++) {
        final cell = cells[c];
        // 빈 칸은 아예 적지 않는다. 엑셀이 알아서 빈 칸으로 본다.
        if (cell == null || cell.isEmpty) continue;
        final ref = '${columnName(c)}${r + 1}';
        if (cell._number != null) {
          data.write('<c r="$ref"><v>${cell._number}</v></c>');
        } else {
          // 공유 문자열 표를 만들지 않고 칸에 바로 적는다(inlineStr).
          // 표를 따로 두면 파일은 작아지지만 만드는 코드가 배로 는다.
          data.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
              '${_esc(cell._text!)}</t></is></c>');
        }
      }
      data.write('</row>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>$data</sheetData></worksheet>';
  }

  /// 0 -> A, 25 -> Z, 26 -> AA.
  static String columnName(int index) {
    var n = index;
    final out = StringBuffer();
    while (true) {
      out.write(String.fromCharCode(65 + (n % 26)));
      n = n ~/ 26 - 1;
      if (n < 0) break;
    }
    return String.fromCharCodes(out.toString().codeUnits.reversed);
  }

  /// XML 에서 뜻이 있는 글자를 피한다. 환자 이름에 & 가 들어와도 깨지지 않게.
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
