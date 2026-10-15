import { parseDayOrNull, parseTime, parseTimeOrNull } from '../util/dates';

type Json = Record<string, any>;

/// What a file holds: `import_batches.kind` (20261003120000, 20261004120000).
export type ImportKind = 'patients' | 'visits' | 'dental';
export const importKinds: readonly ImportKind[] = ['patients', 'visits', 'dental'];
export const importKindMeta: Record<ImportKind, { label: string; one: string; many: string }> = {
  patients: { label: 'Patients', one: 'patient', many: 'patients' },
  visits: { label: 'Visits', one: 'visit', many: 'visits' },
  dental: { label: 'Dental chart', one: 'chart entry', many: 'chart entries' },
};

/// "1 visit", "3 chart entries".
export function importKindCount(kind: ImportKind, n: number): string {
  const m = importKindMeta[kind];
  return `${n} ${n === 1 ? m.one : m.many}`;
}

export function importKindFromWire(wire: string | null | undefined): ImportKind {
  return wire === 'visits' || wire === 'dental' ? wire : 'patients';
}

/// One import of a file: `public.import_batches`.
export class ImportBatch {
  constructor(
    readonly id: string,
    readonly kind: ImportKind,
    readonly fileName: string,
    readonly createdAt: Date,
    readonly createdBy: string | null,
    readonly created: number,
    readonly updated: number,
    readonly skipped: number,
    readonly failed: number,
    readonly undoneAt: Date | null = null,
  ) {}

  get isUndone(): boolean {
    return this.undoneAt != null;
  }

  static fromJson(json: Json): ImportBatch {
    return new ImportBatch(
      json.id,
      importKindFromWire(json.kind),
      json.file_name,
      parseTime(json.created_at),
      json.created_by ?? null,
      json.created_count ?? 0,
      json.updated_count ?? 0,
      json.skipped_count ?? 0,
      json.failed_count ?? 0,
      parseTimeOrNull(json.undone_at),
    );
  }
}

/// What `import_patients` did, or would do, with one row. `duplicate` looks
/// like a patient already here; not written until someone decides.
export type ImportOutcome = 'created' | 'updated' | 'skipped' | 'duplicate' | 'error';

export function importOutcomeFromWire(wire: string | null | undefined): ImportOutcome {
  return wire === 'created' || wire === 'updated' || wire === 'skipped' || wire === 'duplicate' ? wire : 'error';
}

/// A patient already at the clinic that a row looks like.
export class ImportMatch {
  constructor(
    readonly id: string,
    readonly name: string,
    readonly phone: string | null = null,
    readonly dateOfBirth: Date | null = null,
    readonly chartNumber: string | null = null,
  ) {}

  static fromJson(json: Json): ImportMatch {
    return new ImportMatch(
      json.id,
      json.full_name ?? '',
      json.phone ?? null,
      parseDayOrNull(json.date_of_birth),
      json.chart_number ?? null,
    );
  }
}

export class ImportRowResult {
  constructor(
    /// The row's line in the file.
    readonly row: number,
    readonly outcome: ImportOutcome,
    readonly patientId: string | null = null,
    /// For a duplicate: the patient it looks like.
    readonly match: ImportMatch | null = null,
    readonly message: string | null = null,
    readonly warnings: string[] = [],
  ) {}

  static fromJson(json: Json): ImportRowResult {
    return new ImportRowResult(
      json.row,
      importOutcomeFromWire(json.result),
      json.patient_id ?? null,
      json.match == null ? null : ImportMatch.fromJson(json.match),
      json.message ?? null,
      ((json.warnings ?? []) as unknown[]).map(String),
    );
  }
}

/// What undoing an import did.
export type UndoImportResult = {
  /// What the import had added (patients, visits or chart entries), now gone.
  removed: number;
  /// Patients already on file that it changed; those changes stay.
  keptUpdates: number;
};
