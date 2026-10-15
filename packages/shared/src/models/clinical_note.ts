import { parseTimeOrNull } from '../util/dates';

type Json = Record<string, any>;

/// Clinical text: the standing medical note on a chart (`chart_notes`) or the
/// consultation note on a visit (`visit_notes`).
///
/// Only a clinic's doctors and admins can read or write these rows. For anyone
/// else RLS returns nothing, which looks exactly like "no note on file" — so a
/// screen decides whether to show a notes section from `useCanSeeClinicalNotes`,
/// never from whether a note came back.
export class ClinicalNote {
  constructor(
    readonly body: string,
    readonly updatedAt: Date | null = null,
    /// Profile id of whoever last wrote it. Stamped by the database from the
    /// session, so it cannot be spoofed by the client.
    readonly updatedBy: string | null = null,
  ) {}

  get isEmpty(): boolean {
    return this.body.trim() === '';
  }

  static fromJson(json: Json): ClinicalNote {
    return new ClinicalNote(json.body ?? '', parseTimeOrNull(json.updated_at), json.updated_by ?? null);
  }

  /// A row, an embed, or nothing.
  ///
  /// PostgREST may return an embedded note as an object or as a one-element
  /// list depending on how it reads the foreign key, so both are accepted. A
  /// blank note is treated as no note: clearing one keeps the row (and who
  /// cleared it) rather than deleting it.
  static fromNullableJson(json: unknown): ClinicalNote | null {
    const row = Array.isArray(json) ? (json.length === 0 ? null : json[0]) : json;
    if (row == null || typeof row !== 'object') return null;
    const note = ClinicalNote.fromJson(row as Json);
    return note.isEmpty ? null : note;
  }
}
