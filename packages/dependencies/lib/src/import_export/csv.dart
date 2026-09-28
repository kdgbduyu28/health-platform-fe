/// CSV as spreadsheets write it (RFC 4180): quoted fields may hold commas,
/// line breaks and doubled quotes.
///
/// Reading takes what Excel and Google Sheets save: a UTF-8 byte order mark,
/// CRLF or LF line ends, and a semicolon instead of a comma where the
/// computer's region uses the comma for decimals. Writing produces what Excel
/// opens correctly: a BOM (without it Excel reads "Peña" as "PeÃ±a") and CRLF.
library;

/// The rows of [text], every row a list of fields. Blank rows are dropped.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final delimiter = _guessDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // A spreadsheet's trailing ",,,," rows are blank too.
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      quoted = true;
    } else if (c == delimiter) {
      endField();
    } else if (c == '\r' || c == '\n') {
      endRow();
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Comma, unless the header line has more semicolons (or tabs) outside
/// quotes than commas.
String _guessDelimiter(String text) {
  final counts = {',': 0, ';': 0, '\t': 0};
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') quoted = !quoted;
    if (quoted) continue;
    if (c == '\n' || c == '\r') break;
    if (counts.containsKey(c)) counts[c] = counts[c]! + 1;
  }
  var best = ',';
  for (final e in counts.entries) {
    if (e.value > counts[best]!) best = e.key;
  }
  return best;
}

/// [rows] as a CSV file's text, BOM first. Null writes an empty field.
String toCsv(List<List<Object?>> rows) {
  final out = StringBuffer('﻿');
  for (final row in rows) {
    out.write(row.map(_escape).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

String _escape(Object? value) {
  final s = value?.toString() ?? '';
  // A leading =, +, - or @ makes a spreadsheet run the cell as a formula
  // (CSV injection). Patient data is typed by the public, so an apostrophe
  // keeps it text; [unescapeCell] takes it off again on import. A phone
  // number or amount ("+63 917…", "-150") is left alone.
  final safe = _looksLikeFormula(s) ? "'$s" : s;
  if (safe.contains(RegExp(r'[",\r\n;]'))) {
    return '"${safe.replaceAll('"', '""')}"';
  }
  return safe;
}

bool _looksLikeFormula(String s) {
  if (s.isEmpty) return false;
  if (s[0] == '=' || s[0] == '@') return true;
  return (s[0] == '+' || s[0] == '-') && !RegExp(r'^[+-][\d\s().,-]*$').hasMatch(s);
}

/// A cell as typed, without the apostrophe [toCsv] put in front of a
/// formula-looking value.
String unescapeCell(String cell) =>
    cell.length > 1 && cell[0] == "'" && _looksLikeFormula(cell.substring(1))
        ? cell.substring(1)
        : cell;
