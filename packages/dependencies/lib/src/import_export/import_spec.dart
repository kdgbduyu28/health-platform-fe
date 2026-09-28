import '../models/data_import.dart';
import '../models/dental_chart.dart';
import 'dental_columns.dart';
import 'import_common.dart';
import 'patient_columns.dart';
import 'visit_columns.dart';

/// How the person said to read the file, beyond its columns.
class ImportSettings {
  const ImportSettings({
    this.dateOrder = DateOrder.monthFirst,
    this.numbering = ToothNumbering.fdi,
    this.doctors = const {},
  });

  final DateOrder dateOrder;
  final ToothNumbering numbering;

  /// Visits: each doctor name in the file (cleaned) → the roster doctor.
  final Map<String, String> doctors;
}

/// What differs between importing patients, visits and a dental chart; the
/// import screen does the rest the same way for all three.
sealed class ImportSpec {
  const ImportSpec();

  factory ImportSpec.of(ImportKind kind) => switch (kind) {
        ImportKind.patients => const PatientsSpec(),
        ImportKind.visits => const VisitsSpec(),
        ImportKind.dental => const DentalSpec(),
      };

  ImportKind get kind;

  /// What the column picker offers.
  List<ImportColumn> get columns;

  List<ImportColumn?> match(List<String> headers);

  /// Why the check cannot run yet with these columns, or null.
  String? missing(List<ImportColumn?> columns);

  /// Columns only doctors and admins may import (notes).
  Set<ImportColumn> get clinicianColumns;

  /// Columns holding dates, which need a day/month order.
  Set<ImportColumn> get dateColumns;

  /// Visits: the column naming the doctor, matched to the roster first.
  ImportColumn? get doctorColumn => null;

  /// Dental: tooth numbers need a numbering system.
  bool get asksNumbering => false;

  ImportRow read(List<String> cells, List<ImportColumn?> columns, int row, ImportSettings s);

  /// Keys that make two rows of one file the same record. Patients only:
  /// the database finds repeated visits and chart entries itself.
  List<String> sameRecordKeys(ImportRow r) => const [];

  /// The header row and the template.
  List<String> get templateHeaders;
}

class PatientsSpec extends ImportSpec {
  const PatientsSpec();

  @override
  ImportKind get kind => ImportKind.patients;
  @override
  List<ImportColumn> get columns => PatientColumn.importable;
  @override
  List<ImportColumn?> match(List<String> headers) => matchHeaders(headers);
  @override
  String? missing(List<ImportColumn?> c) =>
      c.contains(PatientColumn.fullName) ||
              c.contains(PatientColumn.firstName) ||
              c.contains(PatientColumn.lastName)
          ? null
          : 'Pick the column with the patient\'s name.';
  @override
  Set<ImportColumn> get clinicianColumns => {PatientColumn.chartNote};
  @override
  Set<ImportColumn> get dateColumns => {PatientColumn.dateOfBirth, PatientColumn.signedOn};
  @override
  ImportRow read(List<String> cells, List<ImportColumn?> c, int row, ImportSettings s) =>
      readPatientRow(cells, c.cast<PatientColumn?>(), row: row, dateOrder: s.dateOrder);
  @override
  List<String> sameRecordKeys(ImportRow r) {
    final person = r.json['person'] as Map<String, dynamic>;
    final name = r.name.toLowerCase();
    final digits = (person['phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
    return [
      if (r.json['chart_number'] case final String n) 'chart:${n.toLowerCase()}',
      if (digits.length >= 7) 'phone:$name|$digits',
      if (person['date_of_birth'] case final String d) 'dob:$name|$d',
    ];
  }

  @override
  List<String> get templateHeaders => [for (final c in PatientColumn.template) c.header];
}

class VisitsSpec extends ImportSpec {
  const VisitsSpec();

  @override
  ImportKind get kind => ImportKind.visits;
  @override
  List<ImportColumn> get columns => VisitColumn.values;
  @override
  List<ImportColumn?> match(List<String> headers) => VisitColumn.match(headers);
  @override
  String? missing(List<ImportColumn?> c) {
    if (!c.contains(VisitColumn.patientId) &&
        !c.contains(VisitColumn.chartNumber) &&
        !c.contains(VisitColumn.patientName)) {
      return 'Pick the column that names the patient (name or chart no.).';
    }
    if (!c.contains(VisitColumn.date)) return 'Pick the column with the visit date.';
    return null;
  }

  @override
  Set<ImportColumn> get clinicianColumns => {VisitColumn.visitNote, VisitColumn.patientNote};
  @override
  Set<ImportColumn> get dateColumns => {VisitColumn.date, VisitColumn.patientBirthday};
  @override
  ImportColumn get doctorColumn => VisitColumn.doctor;
  @override
  ImportRow read(List<String> cells, List<ImportColumn?> c, int row, ImportSettings s) =>
      readVisitRow(cells, c.cast<VisitColumn?>(),
          row: row, doctors: s.doctors, dateOrder: s.dateOrder);
  @override
  List<String> get templateHeaders => [for (final c in VisitColumn.template) c.header];
}

class DentalSpec extends ImportSpec {
  const DentalSpec();

  @override
  ImportKind get kind => ImportKind.dental;
  @override
  List<ImportColumn> get columns => DentalColumn.values;
  @override
  List<ImportColumn?> match(List<String> headers) => DentalColumn.match(headers);
  @override
  String? missing(List<ImportColumn?> c) {
    if (!c.contains(DentalColumn.patientId) &&
        !c.contains(DentalColumn.chartNumber) &&
        !c.contains(DentalColumn.patientName)) {
      return 'Pick the column that names the patient (name or chart no.).';
    }
    if (!c.contains(DentalColumn.tooth)) return 'Pick the column with the tooth.';
    if (!c.contains(DentalColumn.code)) return 'Pick the column with the finding or treatment.';
    return null;
  }

  @override
  Set<ImportColumn> get clinicianColumns => const {};
  @override
  Set<ImportColumn> get dateColumns => {DentalColumn.date, DentalColumn.patientBirthday};
  @override
  bool get asksNumbering => true;
  @override
  ImportRow read(List<String> cells, List<ImportColumn?> c, int row, ImportSettings s) =>
      readDentalRow(cells, c.cast<DentalColumn?>(),
          row: row, dateOrder: s.dateOrder, numbering: s.numbering);
  @override
  List<String> get templateHeaders => [for (final c in DentalColumn.template) c.header];
}

/// An export's header row and one row's cells, for [kind].
({List<String> headers, List<String> Function(Map<String, dynamic>) cells}) exportLayout(
    ImportKind kind, {required bool withNotes}) {
  switch (kind) {
    case ImportKind.patients:
      final c = PatientColumn.exported(withNotes: withNotes);
      return (headers: [for (final x in c) x.header], cells: (r) => exportPatientCells(r, c));
    case ImportKind.visits:
      final c = VisitColumn.exported(withNotes: withNotes);
      return (headers: [for (final x in c) x.header], cells: (r) => exportVisitCells(r, c));
    case ImportKind.dental:
      final c = DentalColumn.exported;
      return (headers: [for (final x in c) x.header], cells: (r) => exportDentalCells(r, c));
  }
}
