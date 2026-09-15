/// Clinical text: the standing medical note on a chart (`chart_notes`) or the
/// consultation note on a visit (`visit_notes`).
///
/// Only a clinic's doctors and admins can read or write these rows. For anyone
/// else RLS returns nothing, which looks exactly like "no note on file" — so a
/// screen decides whether to show a notes section from
/// `canSeeClinicalNotesProvider`, never from whether a note came back.
class ClinicalNote {
  const ClinicalNote({required this.body, this.updatedAt, this.updatedBy});

  final String body;
  final DateTime? updatedAt;

  /// Profile id of whoever last wrote it. Stamped by the database from the
  /// session, so it cannot be spoofed by the client.
  final String? updatedBy;

  bool get isEmpty => body.trim().isEmpty;

  factory ClinicalNote.fromJson(Map<String, dynamic> json) => ClinicalNote(
        body: json['body'] as String? ?? '',
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.parse(json['updated_at'] as String).toLocal(),
        updatedBy: json['updated_by'] as String?,
      );

  /// A row, an embed, or nothing.
  ///
  /// PostgREST may return an embedded note as an object or as a one-element
  /// list depending on how it reads the foreign key, so both are accepted. A
  /// blank note is treated as no note: clearing one keeps the row (and who
  /// cleared it) rather than deleting it.
  static ClinicalNote? fromNullableJson(Object? json) {
    final row = json is List ? (json.isEmpty ? null : json.first) : json;
    if (row is! Map<String, dynamic>) return null;
    final note = ClinicalNote.fromJson(row);
    return note.isEmpty ? null : note;
  }
}
