import '../models/appointment_status.dart';
import 'import_common.dart';

/// The columns of a visits file, in and out: `import_visits` and
/// `export_visits` (20261004120000). One row per visit, past or upcoming.
///
/// The patient is named the way the clinic knows them: the chart id from an
/// export, the chart number, or the name (with a phone or birthday to tell
/// namesakes apart). The patients must already be here. The doctor is a name
/// the person importing matches to the roster before the check.
enum VisitColumn implements ImportColumn {
  patientId('patient_id', 'Patient ID', 'from an export', ['id']),
  chartNumber('chart_number', 'Chart no.', 'the clinic\'s record number', [
    'chart number', 'chart', 'record no', 'record number', 'patient no',
    'patient number', 'file no', 'folder no',
  ]),
  patientName('patient_name', 'Patient', 'the patient\'s name', [
    'name', 'patient name', 'full name', 'patient full name', 'pangalan',
  ]),
  patientPhone('patient_phone', 'Phone', 'tells namesakes apart', [
    'mobile', 'mobile no', 'contact', 'contact no', 'contact number',
    'cellphone', 'phone number',
  ]),
  patientBirthday('patient_birthday', 'Birthday', 'tells namesakes apart',
      ['birthdate', 'date of birth', 'dob']),
  date('date', 'Date', 'the day of the visit', [
    'visit date', 'date of visit', 'appointment date', 'schedule', 'petsa',
    'date seen', 'consultation date',
  ]),
  time('time', 'Time', '9:00, 2:30 PM; 9:00 when blank (past visits)',
      ['visit time', 'appointment time', 'oras']),
  doctor('doctor', 'Doctor', 'matched to the roster next', [
    'dentist', 'physician', 'attending', 'attending dentist', 'doctor name',
    'seen by', 'provider',
  ]),
  service('service', 'Service', 'one of your services, or as typed', [
    'procedure', 'treatment', 'treatment done', 'service rendered',
    'services', 'reason', 'procedure done',
  ]),
  duration('duration_minutes', 'Minutes', 'for a service not in your list',
      ['duration', 'length', 'mins']),
  status('status', 'Status',
      'Completed, Cancelled or No-show; Pending or Confirmed ahead', ['remarks status']),
  visitNote('visit_note', 'Visit notes', 'doctors and admins only', [
    'notes', 'note', 'clinical notes', 'findings', 'remarks', 'treatment notes',
    'progress notes', 'diagnosis',
  ]),
  patientNote('patient_note', 'Note to patient', 'doctors and admins only',
      ['instructions', 'advice', 'patient note']);

  const VisitColumn(this.key, this.header, this.hint, this.aliases);

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

  static List<VisitColumn?> match(List<String> headers) =>
      matchColumns(headers, VisitColumn.values);

  /// An exported file's columns. The front desk's has no visit notes: they
  /// cannot read them, and a blank column looks like "no notes".
  static List<VisitColumn> exported({required bool withNotes}) => [
        for (final c in values)
          if (c != patientPhone && c != patientBirthday && (withNotes || c != visitNote)) c,
      ];

  static List<VisitColumn> get template => [
        for (final c in values) if (c != patientId) c,
      ];
}

/// A doctor's name as files and rosters write it, for matching the two:
/// no title, no punctuation, lower case. "Dra. Ma. Santos, DMD" is
/// "ma santos".
String doctorKey(String name) => normHeader(name)
    .split(' ')
    .where((w) => !const {'dr', 'dra', 'doc', 'doctor', 'dmd', 'dds', 'md'}.contains(w))
    .join(' ');

/// The roster doctor [fileName] means: the same name, or the only one whose
/// name contains it ("Santos" for "Maria Santos"). Null when none or several.
String? matchDoctor(String fileName, Map<String, String> rosterByName) {
  final key = doctorKey(fileName);
  if (key.isEmpty) return null;
  final keys = {for (final e in rosterByName.entries) doctorKey(e.key): e.value};
  if (keys[key] case final id?) return id;
  final words = key.split(' ');
  final hits = {
    for (final e in keys.entries)
      if (words.every((w) => e.key.split(' ').contains(w))) e.value,
  };
  return hits.length == 1 ? hits.single : null;
}

/// A status as files write it; null if it is not one.
AppointmentStatus? parseVisitStatus(String raw) =>
    switch (normHeader(raw)) {
      'completed' || 'complete' || 'done' || 'finished' || 'attended' || 'seen' ||
      'served' =>
        AppointmentStatus.completed,
      'cancelled' || 'canceled' || 'cancel' => AppointmentStatus.cancelled,
      'no show' || 'noshow' || 'missed' || 'absent' || 'did not come' =>
        AppointmentStatus.noShow,
      'pending' || 'requested' => AppointmentStatus.pending,
      'confirmed' || 'booked' || 'scheduled' => AppointmentStatus.confirmed,
      // An export taken mid-day; the database says whether it can go in.
      'waiting' || 'arrived' => AppointmentStatus.arrived,
      'with doctor' || 'in consultation' => AppointmentStatus.inConsultation,
      _ => null,
    };

/// Reads one row of a visits file. [doctors] maps each doctor name as the
/// file writes it (cleaned) to the roster doctor it was matched to.
ImportRow readVisitRow(
  List<String> cells,
  List<VisitColumn?> columns, {
  required int row,
  required Map<String, String> doctors,
  DateOrder dateOrder = DateOrder.monthFirst,
}) {
  final errors = <String>[];
  final v = <VisitColumn, String>{};
  for (var i = 0; i < columns.length && i < cells.length; i++) {
    final c = columns[i];
    if (c == null) continue;
    final s = cleanCell(cells[i]);
    if (s.isNotEmpty) v[c] = s;
  }

  final json = <String, dynamic>{
    'row': row,
    ...readPatientRef(
      patientId: v[VisitColumn.patientId],
      chartNumber: v[VisitColumn.chartNumber],
      name: v[VisitColumn.patientName],
      phone: v[VisitColumn.patientPhone],
    ),
  };
  if (!json.containsKey('patient_id') &&
      !json.containsKey('chart_number') &&
      !json.containsKey('patient_name')) {
    errors.add('No patient: give a chart number or a name.');
  }
  if (v[VisitColumn.patientBirthday] case final raw?) {
    final d = parseDate(raw, dateOrder);
    if (d == null) {
      errors.add('Birthday "$raw" is not a date.');
    } else {
      json['patient_birthday'] = isoDate(d);
    }
  }

  switch (v[VisitColumn.date]) {
    case null:
      errors.add('No date.');
    case final raw:
      final d = parseDate(raw, dateOrder);
      if (d == null) {
        errors.add('Date "$raw" is not a date.');
      } else {
        json['date'] = isoDate(d);
      }
  }
  if (v[VisitColumn.time] case final raw?) {
    final t = parseTime(raw);
    if (t == null) {
      errors.add('Time "$raw" is not a time.');
    } else {
      json['time'] = t;
    }
  }

  final doctor = v[VisitColumn.doctor] ?? '';
  if (doctors[doctor] case final id?) {
    json['doctor_id'] = id;
  } else {
    errors.add(doctor.isEmpty
        ? 'No doctor: pick one for the rows without a name.'
        : 'Doctor "$doctor" is not matched to anyone on the roster.');
  }

  if (v[VisitColumn.service] case final s?) json['service'] = s;
  if (v[VisitColumn.duration] case final raw?) {
    final m = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (m == null || m < 5 || m > 480) {
      errors.add('Minutes "$raw" is not between 5 and 480.');
    } else {
      json['duration_minutes'] = m;
    }
  }
  if (v[VisitColumn.status] case final raw?) {
    final s = parseVisitStatus(raw);
    if (s == null) {
      errors.add('Status "$raw" is not Completed, Cancelled, No-show, Pending or Confirmed.');
    } else {
      json['status'] = s.wire;
    }
  }
  if (v[VisitColumn.visitNote] case final n?) json['visit_note'] = n;
  if (v[VisitColumn.patientNote] case final n?) json['patient_note'] = n;

  return ImportRow(
    row: row,
    json: json,
    name: [
      json['patient_name'] ?? json['chart_number'] ?? 'Patient',
      json['date'],
    ].whereType<String>().join(' · '),
    errors: errors,
    cells: cells,
  );
}

/// One export_visits row as the cells of [columns].
List<String> exportVisitCells(Map<String, dynamic> v, List<VisitColumn> columns) => [
      for (final c in columns)
        switch (c) {
          VisitColumn.status => AppointmentStatus.values
                  .where((s) => s.wire == v['status'])
                  .firstOrNull
                  ?.displayName ??
              '${v['status'] ?? ''}',
          _ => v[c.key]?.toString() ?? '',
        },
    ];
