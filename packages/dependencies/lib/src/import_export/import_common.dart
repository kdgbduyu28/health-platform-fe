import 'package:intl/intl.dart';

import 'csv.dart';

/// What every kind of file (patients, visits, dental chart) shares: its
/// columns, how a header is recognised, how a row comes out, and reading
/// cells as clinics type them.

/// One column a file can have.
abstract interface class ImportColumn {
  /// The key in the import function's row JSON and the export's output.
  String get key;

  /// The header an exported file and the template carry.
  String get header;

  /// Other headers clinics use for it.
  List<String> get aliases;

  /// What goes in it, for the column picker.
  String get hint;

  /// Read-only facts an export adds; an import ignores them.
  bool get exportOnly;
}

/// Each of [headers]' columns as the one of [columns] it most likely holds,
/// or none. A column is used at most once: the first header that names it.
List<T?> matchColumns<T extends ImportColumn>(List<String> headers, List<T> columns) {
  final used = <T>{};
  return [
    for (final h in headers)
      () {
        final n = normHeader(h);
        for (final c in columns) {
          if (c.exportOnly || used.contains(c)) continue;
          if (normHeader(c.header) == n ||
              normHeader(c.key) == n ||
              c.aliases.any((a) => normHeader(a) == n)) {
            used.add(c);
            return c;
          }
        }
        return null;
      }(),
  ];
}

/// "Mobile No." and "mobile_no" are the same header.
String normHeader(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// One row of a file, read: the JSON an import function takes, or why not.
class ImportRow {
  ImportRow({
    required this.row,
    required this.json,
    required this.name,
    List<String>? errors,
    this.warnings = const [],
    this.cells = const [],
  }) : errors = errors ?? [];

  /// Its line in the file (the header is 1).
  final int row;
  final Map<String, dynamic> json;

  /// Who the row is about, to list it by.
  final String name;

  /// What stops it being imported. Checked here, before the database sees it.
  final List<String> errors;
  final List<String> warnings;

  /// The row as it was in the file, for the "rows that failed" download.
  final List<String> cells;

  bool get ok => errors.isEmpty;
}

/// How a file writes dates such as 03/04/1990. An ISO date (1990-04-03) and a
/// written-out one (April 3, 1990) read the same either way.
enum DateOrder {
  monthFirst('Month first (03/04/1990 is March 4)'),
  dayFirst('Day first (03/04/1990 is 3 April)');

  const DateOrder(this.label);
  final String label;
}

/// Placeholders that mean "nothing written here".
const blankWords = {'-', '--', 'n/a', 'na', 'none', 'wala', 'nil', 'null'};

/// A cell trimmed, one space between words, and empty for a placeholder.
String cleanCell(String raw) {
  final s = unescapeCell(raw.trim()).replaceAll(RegExp(r'\s+'), ' ');
  return blankWords.contains(s.toLowerCase()) ? '' : s;
}

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// "JUAN DELA CRUZ" and "Dela Cruz, Juan" as "Juan Dela Cruz". A name typed
/// in mixed case is left as typed.
String tidyName(String name) {
  var n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final parts = n.split(',');
  if (parts.length == 2 &&
      parts[0].trim().isNotEmpty &&
      parts[1].trim().isNotEmpty &&
      !_suffixes.contains(normHeader(parts[1]))) {
    n = '${parts[1].trim()} ${parts[0].trim()}';
  }
  if (n == n.toUpperCase() && n != n.toLowerCase()) {
    n = n.toLowerCase().splitMapJoin(RegExp(r'\p{L}+', unicode: true),
        onMatch: (m) => '${m[0]![0].toUpperCase()}${m[0]!.substring(1)}');
  }
  return n;
}

/// "Juan dela Cruz, Jr." is not "Jr. Juan dela Cruz".
const _suffixes = {'jr', 'sr', 'ii', 'iii', 'iv', 'v'};

final _written = [
  DateFormat('MMMM d, y'), DateFormat('MMM d, y'), DateFormat('MMM. d, y'),
  DateFormat('d MMMM y'), DateFormat('d MMM y'), DateFormat('d-MMM-y'),
];

/// A date as clinics write them; null if it is not one.
DateTime? parseDate(String raw, DateOrder order) {
  final s = raw.trim();
  // ISO, with or without a time after it.
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (iso != null) {
    return _date(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  }
  final slashed = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$').firstMatch(s);
  if (slashed != null) {
    final a = int.parse(slashed[1]!), b = int.parse(slashed[2]!);
    var y = int.parse(slashed[3]!);
    if (slashed[3]!.length == 2) {
      // 90 is 1990, 05 is 2005: never a year still to come.
      y += 2000;
      if (y > DateTime.now().year) y -= 100;
    }
    return order == DateOrder.monthFirst ? _date(y, a, b) : _date(y, b, a);
  }
  for (final f in _written) {
    try {
      final d = f.parseStrict(s);
      return DateTime(d.year, d.month, d.day);
    } on FormatException {
      continue;
    }
  }
  return null;
}

DateTime? _date(int y, int m, int d) {
  if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  // DateTime rolls 31 April over into May; a real date does not.
  return date.month == m && date.day == d ? date : null;
}

/// A time of day as "HH:MM": "9:00", "9.30", "2 PM", "2:30pm", "14:30".
/// Null if it is not one.
String? parseTime(String raw) {
  final m = RegExp(r'^(\d{1,2})(?:[:.](\d{2}))?(?::\d{2})?\s*([ap])?\.?\s*m?\.?$',
          caseSensitive: false)
      .firstMatch(raw.trim());
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = int.parse(m[2] ?? '0');
  final half = m[3]?.toLowerCase();
  // A bare "9" is a number, not a time.
  if (m[2] == null && half == null) return null;
  if (half != null) {
    if (h < 1 || h > 12) return null;
    h = h % 12 + (half == 'p' ? 12 : 0);
  }
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// Yes/No as clinics answer it, English or Filipino. Null: not an answer.
bool? parseYesNo(String raw) => switch (raw.trim().toLowerCase()) {
      'yes' || 'y' || 'true' || '1' || 'oo' || 'opo' || '✓' || 'x' => true,
      'no' || 'n' || 'false' || '0' || 'hindi' || 'di' => false,
      _ => null,
    };

/// "₱1,500.50", "PHP 1500", "1500" — pesos, as a number.
double? parsePesos(String raw) {
  final s = raw.replaceAll(RegExp(r'php|₱|p|,|\s', caseSensitive: false), '');
  return double.tryParse(s);
}

/// The patient a visit or chart row is about, as the import functions find
/// them (`private.import_find_patient`): chart id, chart number, or a name
/// with a phone or birthday to tell namesakes apart.
Map<String, dynamic> readPatientRef({
  String? patientId,
  String? chartNumber,
  String? name,
  String? phone,
  String? birthday,
}) =>
    {
      if (patientId != null) 'patient_id': patientId,
      if (chartNumber != null) 'chart_number': chartNumber,
      if (name != null) 'patient_name': tidyName(name),
      if (phone != null) 'patient_phone': phone,
      if (birthday != null) 'patient_birthday': birthday,
    };
