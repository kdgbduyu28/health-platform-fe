import '../models/dental_chart.dart';
import 'import_common.dart';

/// The columns of a dental chart file, in and out: `import_dental` and
/// `export_dental` (20261004120000). One row per thing known about one tooth,
/// as the chart keeps it ([DentalEntry]).
///
/// Teeth are FDI in an export. An import also reads Universal numbering
/// (1–32, A–T) when the person says the file uses it.
enum DentalColumn implements ImportColumn {
  patientId('patient_id', 'Patient ID', 'from an export', ['id']),
  chartNumber('chart_number', 'Chart no.', 'the clinic\'s record number', [
    'chart number', 'chart', 'record no', 'record number', 'patient no',
    'patient number', 'file no', 'folder no',
  ]),
  patientName('patient_name', 'Patient', 'the patient\'s name',
      ['name', 'patient name', 'full name', 'pangalan']),
  patientPhone('patient_phone', 'Phone', 'tells namesakes apart',
      ['mobile', 'mobile no', 'contact', 'contact no', 'contact number']),
  patientBirthday('patient_birthday', 'Birthday', 'tells namesakes apart',
      ['birthdate', 'date of birth', 'dob']),
  tooth('tooth', 'Tooth', '16, 36 (FDI) or 3, A (Universal)',
      ['tooth no', 'tooth number', 'tooth #', 'ngipin']),
  surfaces('surfaces', 'Surfaces', 'M O D B L, as in MOD', ['surface', 'surfaces involved']),
  code('code', 'Finding / treatment', 'Decay, Filling, Crown, Extraction…', [
    'finding', 'treatment', 'procedure', 'condition', 'diagnosis', 'code',
    'treatment done', 'work',
  ]),
  status('status', 'Status', 'On exam, Planned or Done', ['state']),
  date('date', 'Date', 'the visit it was found, planned or done at',
      ['visit date', 'date done', 'date of visit', 'petsa']),
  note('note', 'Note', 'up to 500 characters', ['notes', 'remarks', 'comment']);

  const DentalColumn(this.key, this.header, this.hint, this.aliases);

  @override
  final String key;
  @override
  final String header;
  @override
  final String hint;
  @override
  final List<String> aliases;
  @override
  bool get exportOnly => false;

  static List<DentalColumn?> match(List<String> headers) =>
      matchColumns(headers, DentalColumn.values);

  static List<DentalColumn> get exported => [
        for (final c in values)
          if (c != patientPhone && c != patientBirthday) c,
      ];

  static List<DentalColumn> get template => [
        for (final c in values) if (c != patientId) c,
      ];
}

/// Every FDI tooth: 11–18 … 41–48, then primary 51–55 … 81–85.
final List<int> fdiTeeth = [
  for (final q in [1, 2, 3, 4]) for (var p = 1; p <= 8; p++) q * 10 + p,
  for (final q in [5, 6, 7, 8]) for (var p = 1; p <= 5; p++) q * 10 + p,
];

final Map<String, int> _universal = {
  for (final t in fdiTeeth) universalLabel(t): t,
};

/// A tooth as the file writes it, as FDI; null if it is not one. Letters
/// A–T are always Universal primary teeth.
int? parseTooth(String raw, ToothNumbering numbering) {
  final s = raw.trim().toUpperCase().replaceAll(RegExp(r'^#|^TOOTH\s*'), '');
  if (RegExp(r'^[A-T]$').hasMatch(s)) return _universal[s];
  final n = int.tryParse(s);
  if (n == null) return null;
  if (numbering == ToothNumbering.universal) return _universal['$n'];
  return fdiTeeth.contains(n) ? n : null;
}

/// "MOD", "M, O", "mesial occlusal", "IF" (incisal, facial) as the chart's
/// five surfaces. Null if something in it is not a surface.
List<String>? parseSurfaces(String raw) {
  final words = raw.toLowerCase().split(RegExp(r'[\s,;/+-]+')).where((w) => w.isNotEmpty);
  final out = <String>{};
  for (final w in words) {
    final whole = _surfaceWords[w];
    if (whole != null) {
      out.add(whole);
      continue;
    }
    for (final ch in w.split('')) {
      final s = _surfaceLetters[ch];
      if (s == null) return null;
      out.add(s);
    }
  }
  return [for (final s in const ['B', 'D', 'L', 'M', 'O']) if (out.contains(s)) s];
}

const _surfaceWords = {
  'mesial': 'M', 'occlusal': 'O', 'incisal': 'O', 'distal': 'D',
  'buccal': 'B', 'facial': 'B', 'labial': 'B', 'lingual': 'L', 'palatal': 'L',
};

/// Front teeth are charted Incisal and Facial; the same surfaces as O and B.
const _surfaceLetters = {
  'm': 'M', 'o': 'O', 'i': 'O', 'd': 'D', 'b': 'B', 'f': 'B', 'l': 'L', 'p': 'L',
};

/// What an entry records, as clinics write it (English, the chart's
/// abbreviations, and a few Filipino words). Null if it is none of them.
DentalCode? parseDentalCode(String raw) {
  final n = normHeader(raw);
  for (final c in DentalCode.values) {
    if (n == normHeader(c.wire) || n == normHeader(c.label)) return c;
  }
  return _codeWords[n];
}

const _codeWords = {
  'decay': DentalCode.caries, 'carious': DentalCode.caries, 'cavity': DentalCode.caries,
  'cavities': DentalCode.caries, 'car': DentalCode.caries, 'sira': DentalCode.caries,
  'fractured': DentalCode.fracture, 'broken': DentalCode.fracture, 'fx': DentalCode.fracture,
  'chipped': DentalCode.fracture,
  'absent': DentalCode.missing, 'm': DentalCode.missing,
  'imp': DentalCode.impacted, 'monitor': DentalCode.watch, 'w': DentalCode.watch,
  'filled': DentalCode.filling, 'restoration': DentalCode.filling,
  'composite': DentalCode.filling, 'amalgam': DentalCode.filling,
  'pasta': DentalCode.filling, 'f': DentalCode.filling, 'gic': DentalCode.filling,
  'glass ionomer': DentalCode.filling, 'temporary filling': DentalCode.filling,
  's': DentalCode.sealant, 'fissure sealant': DentalCode.sealant, 'pit and fissure sealant': DentalCode.sealant,
  'v': DentalCode.veneer,
  'jacket': DentalCode.crown, 'jacket crown': DentalCode.crown, 'cap': DentalCode.crown,
  'cr': DentalCode.crown, 'pfm': DentalCode.crown, 'porcelain crown': DentalCode.crown,
  'br': DentalCode.bridge, 'pontic': DentalCode.bridge, 'fixed bridge': DentalCode.bridge,
  'rct': DentalCode.rootCanal, 'endo': DentalCode.rootCanal, 'root canal treatment': DentalCode.rootCanal,
  'root canal therapy': DentalCode.rootCanal,
  'x': DentalCode.extraction, 'extracted': DentalCode.extraction, 'exo': DentalCode.extraction,
  'exodontia': DentalCode.extraction, 'extract': DentalCode.extraction, 'bunot': DentalCode.extraction,
  'tooth extraction': DentalCode.extraction,
};

DentalEntryStatus? parseDentalStatus(String raw) => switch (normHeader(raw)) {
      'existing' || 'on exam' || 'present' || 'old' || 'found' => DentalEntryStatus.existing,
      'planned' || 'plan' || 'to do' || 'todo' || 'for treatment' || 'recommended' =>
        DentalEntryStatus.planned,
      'done' || 'completed' || 'treated' || 'performed' => DentalEntryStatus.done,
      _ => null,
    };

/// Reads one row of a dental chart file.
ImportRow readDentalRow(
  List<String> cells,
  List<DentalColumn?> columns, {
  required int row,
  DateOrder dateOrder = DateOrder.monthFirst,
  ToothNumbering numbering = ToothNumbering.fdi,
}) {
  final errors = <String>[];
  final v = <DentalColumn, String>{};
  for (var i = 0; i < columns.length && i < cells.length; i++) {
    final c = columns[i];
    if (c == null) continue;
    final s = cleanCell(cells[i]);
    if (s.isNotEmpty) v[c] = s;
  }

  final json = <String, dynamic>{
    'row': row,
    ...readPatientRef(
      patientId: v[DentalColumn.patientId],
      chartNumber: v[DentalColumn.chartNumber],
      name: v[DentalColumn.patientName],
      phone: v[DentalColumn.patientPhone],
    ),
  };
  if (!json.containsKey('patient_id') &&
      !json.containsKey('chart_number') &&
      !json.containsKey('patient_name')) {
    errors.add('No patient: give a chart number or a name.');
  }
  if (v[DentalColumn.patientBirthday] case final raw?) {
    final d = parseDate(raw, dateOrder);
    if (d == null) {
      errors.add('Birthday "$raw" is not a date.');
    } else {
      json['patient_birthday'] = isoDate(d);
    }
  }

  switch (v[DentalColumn.tooth]) {
    case null:
      errors.add('No tooth.');
    case final raw:
      final t = parseTooth(raw, numbering);
      if (t == null) {
        errors.add('Tooth "$raw" is not a ${numbering.displayName} tooth number.');
      } else {
        json['tooth'] = t;
      }
  }
  switch (v[DentalColumn.code]) {
    case null:
      errors.add('No finding or treatment.');
    case final raw:
      final c = parseDentalCode(raw);
      if (c == null) {
        errors.add('"$raw" is not something the chart records '
            '(${DentalCode.values.map((c) => c.label).join(', ')}).');
      } else {
        json['code'] = c.wire;
      }
  }
  if (v[DentalColumn.surfaces] case final raw?) {
    final s = parseSurfaces(raw);
    if (s == null) {
      errors.add('Surfaces "$raw" are not M, O, D, B or L.');
    } else {
      json['surfaces'] = s;
    }
  }
  if (v[DentalColumn.status] case final raw?) {
    final s = parseDentalStatus(raw);
    if (s == null) {
      errors.add('Status "$raw" is not On exam, Planned or Done.');
    } else {
      json['status'] = s.wire;
    }
  }
  if (v[DentalColumn.date] case final raw?) {
    final d = parseDate(raw, dateOrder);
    if (d == null) {
      errors.add('Date "$raw" is not a date.');
    } else {
      json['date'] = isoDate(d);
    }
  }
  if (v[DentalColumn.note] case final n?) {
    if (n.length > 500) errors.add('The note is longer than 500 characters.');
    json['note'] = n;
  }

  return ImportRow(
    row: row,
    json: json,
    name: [
      json['patient_name'] ?? json['chart_number'] ?? 'Patient',
      if (json['tooth'] != null) 'tooth ${json['tooth']}',
    ].join(' · '),
    errors: errors,
    cells: cells,
  );
}

/// One export_dental row as the cells of [columns].
List<String> exportDentalCells(Map<String, dynamic> e, List<DentalColumn> columns) => [
      for (final c in columns)
        switch (c) {
          DentalColumn.code => DentalCode.values
                  .where((d) => d.wire == e['code'])
                  .firstOrNull
                  ?.label ??
              '${e['code'] ?? ''}',
          DentalColumn.status => DentalEntryStatus.values
                  .where((s) => s.wire == e['status'])
                  .firstOrNull
                  ?.label ??
              '${e['status'] ?? ''}',
          _ => e[c.key]?.toString() ?? '',
        },
    ];
