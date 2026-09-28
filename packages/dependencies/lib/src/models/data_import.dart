/// What a file holds: `import_batches.kind` (20261003120000, 20261004120000).
enum ImportKind {
  patients('patients', 'Patients', 'patient', 'patients'),
  visits('visits', 'Visits', 'visit', 'visits'),
  dental('dental', 'Dental chart', 'chart entry', 'chart entries');

  const ImportKind(this.wire, this.label, this.one, this.many);

  final String wire;
  final String label;
  final String one;
  final String many;

  /// "1 visit", "3 chart entries".
  String count(int n) => '$n ${n == 1 ? one : many}';

  static ImportKind fromWire(String? wire) =>
      values.firstWhere((k) => k.wire == wire, orElse: () => patients);
}

/// One import of a file: `public.import_batches`.
class ImportBatch {
  const ImportBatch({
    required this.id,
    this.kind = ImportKind.patients,
    required this.fileName,
    required this.createdAt,
    required this.createdBy,
    required this.created,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.undoneAt,
  });

  final String id;
  final ImportKind kind;
  final String fileName;
  final DateTime createdAt;
  final String? createdBy;
  final int created;
  final int updated;
  final int skipped;
  final int failed;
  final DateTime? undoneAt;

  bool get isUndone => undoneAt != null;

  factory ImportBatch.fromJson(Map<String, dynamic> json) => ImportBatch(
        id: json['id'] as String,
        kind: ImportKind.fromWire(json['kind'] as String?),
        fileName: json['file_name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        createdBy: json['created_by'] as String?,
        created: json['created_count'] as int? ?? 0,
        updated: json['updated_count'] as int? ?? 0,
        skipped: json['skipped_count'] as int? ?? 0,
        failed: json['failed_count'] as int? ?? 0,
        undoneAt: json['undone_at'] == null
            ? null
            : DateTime.parse(json['undone_at'] as String).toLocal(),
      );
}

/// What `import_patients` did, or would do, with one row.
enum ImportOutcome {
  created,
  updated,
  skipped,

  /// Looks like a patient already here; not written until someone decides.
  duplicate,
  error;

  static ImportOutcome fromWire(String? wire) =>
      values.firstWhere((o) => o.name == wire, orElse: () => error);
}

class ImportRowResult {
  const ImportRowResult({
    required this.row,
    required this.outcome,
    this.patientId,
    this.match,
    this.message,
    this.warnings = const [],
  });

  /// The row's line in the file.
  final int row;
  final ImportOutcome outcome;
  final String? patientId;

  /// For a duplicate: the patient it looks like.
  final ImportMatch? match;
  final String? message;
  final List<String> warnings;

  factory ImportRowResult.fromJson(Map<String, dynamic> json) => ImportRowResult(
        row: json['row'] as int,
        outcome: ImportOutcome.fromWire(json['result'] as String?),
        patientId: json['patient_id'] as String?,
        match: json['match'] == null
            ? null
            : ImportMatch.fromJson(json['match'] as Map<String, dynamic>),
        message: json['message'] as String?,
        warnings: [
          for (final w in json['warnings'] as List<dynamic>? ?? const []) w as String,
        ],
      );
}

/// A patient already at the clinic that a row looks like.
class ImportMatch {
  const ImportMatch({
    required this.id,
    required this.name,
    this.phone,
    this.dateOfBirth,
    this.chartNumber,
  });

  final String id;
  final String name;
  final String? phone;
  final DateTime? dateOfBirth;
  final String? chartNumber;

  factory ImportMatch.fromJson(Map<String, dynamic> json) => ImportMatch(
        id: json['id'] as String,
        name: json['full_name'] as String? ?? '',
        phone: json['phone'] as String?,
        dateOfBirth: json['date_of_birth'] == null
            ? null
            : DateTime.parse(json['date_of_birth'] as String),
        chartNumber: json['chart_number'] as String?,
      );
}

/// What undoing an import did.
class UndoImportResult {
  const UndoImportResult({required this.removed, required this.keptUpdates});

  /// What the import had added (patients, visits or chart entries), now gone.
  final int removed;

  /// Patients already on file that it changed; those changes stay.
  final int keptUpdates;
}
