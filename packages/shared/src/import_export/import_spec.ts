import type { ImportKind } from '../models/data_import';
import type { ToothNumbering } from '../models/dental_chart';
import { DentalColumn, exportDentalCells, readDentalRow } from './dental_columns';
import type { DateOrder, ImportColumn, ImportRow } from './import_common';
import { PatientColumn, exportPatientCells, matchHeaders, readPatientRow } from './patient_columns';
import { VisitColumn, exportVisitCells, readVisitRow } from './visit_columns';

/// How the person said to read the file, beyond its columns.
export type ImportSettings = {
  dateOrder: DateOrder;
  numbering: ToothNumbering;
  /// Visits: each doctor name in the file (cleaned) → the roster doctor.
  doctors: ReadonlyMap<string, string>;
};

export const defaultImportSettings: ImportSettings = { dateOrder: 'month_first', numbering: 'fdi', doctors: new Map() };

/// What differs between importing patients, visits and a dental chart; the
/// import screen does the rest the same way for all three.
export interface ImportSpec {
  readonly kind: ImportKind;
  /// What the column picker offers.
  readonly columns: readonly ImportColumn[];
  match(headers: readonly string[]): (ImportColumn | null)[];
  /// Why the check cannot run yet with these columns, or null.
  missing(columns: readonly (ImportColumn | null)[]): string | null;
  /// Columns only doctors and admins may import (notes).
  readonly clinicianColumns: ReadonlySet<ImportColumn>;
  /// Columns holding dates, which need a day/month order.
  readonly dateColumns: ReadonlySet<ImportColumn>;
  /// Visits: the column naming the doctor, matched to the roster first.
  readonly doctorColumn: ImportColumn | null;
  /// Dental: tooth numbers need a numbering system.
  readonly asksNumbering: boolean;
  read(cells: readonly string[], columns: readonly (ImportColumn | null)[], row: number, s: ImportSettings): ImportRow;
  /// Keys that make two rows of one file the same record. Patients only:
  /// the database finds repeated visits and chart entries itself.
  sameRecordKeys(r: ImportRow): string[];
  /// The header row and the template.
  readonly templateHeaders: string[];
}

const patientsSpec: ImportSpec = {
  kind: 'patients',
  columns: PatientColumn.importable,
  match: (headers) => matchHeaders(headers),
  missing: (c) =>
    c.includes(PatientColumn.fullName) || c.includes(PatientColumn.firstName) || c.includes(PatientColumn.lastName)
      ? null
      : "Pick the column with the patient's name.",
  clinicianColumns: new Set([PatientColumn.chartNote]),
  dateColumns: new Set([PatientColumn.dateOfBirth, PatientColumn.signedOn]),
  doctorColumn: null,
  asksNumbering: false,
  read: (cells, c, row, s) => readPatientRow(cells, c as (PatientColumn | null)[], row, s.dateOrder),
  sameRecordKeys: (r) => {
    const person = r.json.person as Record<string, any>;
    const name = r.name.toLowerCase();
    const digits = String(person.phone ?? '').replace(/\D/g, '');
    return [
      ...(typeof r.json.chart_number === 'string' ? [`chart:${r.json.chart_number.toLowerCase()}`] : []),
      ...(digits.length >= 7 ? [`phone:${name}|${digits}`] : []),
      ...(typeof person.date_of_birth === 'string' ? [`dob:${name}|${person.date_of_birth}`] : []),
    ];
  },
  templateHeaders: PatientColumn.template.map((c) => c.header),
};

const visitsSpec: ImportSpec = {
  kind: 'visits',
  columns: VisitColumn.values,
  match: (headers) => VisitColumn.match(headers),
  missing: (c) => {
    if (!c.includes(VisitColumn.patientId) && !c.includes(VisitColumn.chartNumber) && !c.includes(VisitColumn.patientName)) {
      return 'Pick the column that names the patient (name or chart no.).';
    }
    if (!c.includes(VisitColumn.date)) return 'Pick the column with the visit date.';
    return null;
  },
  clinicianColumns: new Set([VisitColumn.visitNote, VisitColumn.patientNote]),
  dateColumns: new Set([VisitColumn.date, VisitColumn.patientBirthday]),
  doctorColumn: VisitColumn.doctor,
  asksNumbering: false,
  read: (cells, c, row, s) => readVisitRow(cells, c as (VisitColumn | null)[], row, s.doctors, s.dateOrder),
  sameRecordKeys: () => [],
  templateHeaders: VisitColumn.template.map((c) => c.header),
};

const dentalSpec: ImportSpec = {
  kind: 'dental',
  columns: DentalColumn.values,
  match: (headers) => DentalColumn.match(headers),
  missing: (c) => {
    if (!c.includes(DentalColumn.patientId) && !c.includes(DentalColumn.chartNumber) && !c.includes(DentalColumn.patientName)) {
      return 'Pick the column that names the patient (name or chart no.).';
    }
    if (!c.includes(DentalColumn.tooth)) return 'Pick the column with the tooth.';
    if (!c.includes(DentalColumn.code)) return 'Pick the column with the finding or treatment.';
    return null;
  },
  clinicianColumns: new Set(),
  dateColumns: new Set([DentalColumn.date, DentalColumn.patientBirthday]),
  doctorColumn: null,
  asksNumbering: true,
  read: (cells, c, row, s) => readDentalRow(cells, c as (DentalColumn | null)[], row, s.dateOrder, s.numbering),
  sameRecordKeys: () => [],
  templateHeaders: DentalColumn.template.map((c) => c.header),
};

export function importSpecOf(kind: ImportKind): ImportSpec {
  return kind === 'patients' ? patientsSpec : kind === 'visits' ? visitsSpec : dentalSpec;
}

/// An export's header row and one row's cells, for [kind].
export function exportLayout(kind: ImportKind, withNotes: boolean): { headers: string[]; cells: (r: Record<string, any>) => string[] } {
  switch (kind) {
    case 'patients': {
      const c = PatientColumn.exported(withNotes);
      return { headers: c.map((x) => x.header), cells: (r) => exportPatientCells(r, c) };
    }
    case 'visits': {
      const c = VisitColumn.exported(withNotes);
      return { headers: c.map((x) => x.header), cells: (r) => exportVisitCells(r, c) };
    }
    case 'dental': {
      const c = DentalColumn.exported;
      return { headers: c.map((x) => x.header), cells: (r) => exportDentalCells(r, c) };
    }
  }
}
