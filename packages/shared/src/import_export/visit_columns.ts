import { type AppointmentStatus, appointmentStatuses, statusMeta } from '../models/appointment_status';
import {
  type DateOrder,
  type ImportColumn,
  ImportRow,
  cellsByColumn,
  isoDate,
  matchColumns,
  normHeader,
  parseImportDate,
  parseImportTime,
  readPatientRef,
} from './import_common';

/// One column of a visits file, in and out: `import_visits` and
/// `export_visits` (20261004120000). One row per visit, past or upcoming.
///
/// The patient is named the way the clinic knows them: the chart id from an
/// export, the chart number, or the name (with a phone or birthday to tell
/// namesakes apart). The patients must already be here. The doctor is a name
/// the person importing matches to the roster before the check.
export class VisitColumn implements ImportColumn {
  readonly exportOnly = false;

  private constructor(
    readonly key: string,
    readonly header: string,
    readonly hint: string,
    readonly aliases: readonly string[],
  ) {}

  static readonly patientId = new VisitColumn('patient_id', 'Patient ID', 'from an export', ['id']);
  static readonly chartNumber = new VisitColumn('chart_number', 'Chart no.', "the clinic's record number", [
    'chart number', 'chart', 'record no', 'record number', 'patient no', 'patient number', 'file no', 'folder no',
  ]);
  static readonly patientName = new VisitColumn('patient_name', 'Patient', "the patient's name", [
    'name', 'patient name', 'full name', 'patient full name', 'pangalan',
  ]);
  static readonly patientPhone = new VisitColumn('patient_phone', 'Phone', 'tells namesakes apart', [
    'mobile', 'mobile no', 'contact', 'contact no', 'contact number', 'cellphone', 'phone number',
  ]);
  static readonly patientBirthday = new VisitColumn('patient_birthday', 'Birthday', 'tells namesakes apart', ['birthdate', 'date of birth', 'dob']);
  static readonly date = new VisitColumn('date', 'Date', 'the day of the visit', [
    'visit date', 'date of visit', 'appointment date', 'schedule', 'petsa', 'date seen', 'consultation date',
  ]);
  static readonly time = new VisitColumn('time', 'Time', '9:00, 2:30 PM; 9:00 when blank (past visits)', ['visit time', 'appointment time', 'oras']);
  static readonly doctor = new VisitColumn('doctor', 'Doctor', 'matched to the roster next', [
    'dentist', 'physician', 'attending', 'attending dentist', 'doctor name', 'seen by', 'provider',
  ]);
  static readonly service = new VisitColumn('service', 'Service', 'one of your services, or as typed', [
    'procedure', 'treatment', 'treatment done', 'service rendered', 'services', 'reason', 'procedure done',
  ]);
  static readonly duration = new VisitColumn('duration_minutes', 'Minutes', 'for a service not in your list', ['duration', 'length', 'mins']);
  static readonly status = new VisitColumn('status', 'Status', 'Completed, Cancelled or No-show; Pending or Confirmed ahead', ['remarks status']);
  static readonly visitNote = new VisitColumn('visit_note', 'Visit notes', 'doctors and admins only', [
    'notes', 'note', 'clinical notes', 'findings', 'remarks', 'treatment notes', 'progress notes', 'diagnosis',
  ]);
  static readonly patientNote = new VisitColumn('patient_note', 'Note to patient', 'doctors and admins only', ['instructions', 'advice', 'patient note']);

  static readonly values: readonly VisitColumn[] = [
    VisitColumn.patientId, VisitColumn.chartNumber, VisitColumn.patientName, VisitColumn.patientPhone, VisitColumn.patientBirthday,
    VisitColumn.date, VisitColumn.time, VisitColumn.doctor, VisitColumn.service, VisitColumn.duration, VisitColumn.status,
    VisitColumn.visitNote, VisitColumn.patientNote,
  ];

  static match(headers: readonly string[]): (VisitColumn | null)[] {
    return matchColumns(headers, VisitColumn.values);
  }

  /// An exported file's columns. The front desk's has no visit notes: they
  /// cannot read them, and a blank column looks like "no notes".
  static exported(withNotes: boolean): VisitColumn[] {
    return VisitColumn.values.filter(
      (c) => c !== VisitColumn.patientPhone && c !== VisitColumn.patientBirthday && (withNotes || c !== VisitColumn.visitNote),
    );
  }

  static get template(): VisitColumn[] {
    return VisitColumn.values.filter((c) => c !== VisitColumn.patientId);
  }
}

/// A doctor's name as files and rosters write it, for matching the two: no
/// title, no punctuation, lower case. "Dra. Ma. Santos, DMD" is "ma santos".
export function doctorKey(name: string): string {
  const titles = new Set(['dr', 'dra', 'doc', 'doctor', 'dmd', 'dds', 'md']);
  return normHeader(name)
    .split(' ')
    .filter((w) => !titles.has(w))
    .join(' ');
}

/// The roster doctor [fileName] means: the same name, or the only one whose
/// name contains it ("Santos" for "Maria Santos"). Null when none or several.
export function matchDoctor(fileName: string, rosterByName: ReadonlyMap<string, string>): string | null {
  const key = doctorKey(fileName);
  if (key === '') return null;
  const keys = new Map<string, string>();
  for (const [name, id] of rosterByName) keys.set(doctorKey(name), id);
  const exact = keys.get(key);
  if (exact != null) return exact;
  const words = key.split(' ');
  const hits = new Set<string>();
  for (const [k, id] of keys) {
    const parts = k.split(' ');
    if (words.every((w) => parts.includes(w))) hits.add(id);
  }
  return hits.size === 1 ? [...hits][0] : null;
}

/// A status as files write it; null if it is not one.
export function parseVisitStatus(raw: string): AppointmentStatus | null {
  switch (normHeader(raw)) {
    case 'completed':
    case 'complete':
    case 'done':
    case 'finished':
    case 'attended':
    case 'seen':
    case 'served':
      return 'completed';
    case 'cancelled':
    case 'canceled':
    case 'cancel':
      return 'cancelled';
    case 'no show':
    case 'noshow':
    case 'missed':
    case 'absent':
    case 'did not come':
      return 'no_show';
    case 'pending':
    case 'requested':
      return 'pending';
    case 'confirmed':
    case 'booked':
    case 'scheduled':
      return 'confirmed';
    // An export taken mid-day; the database says whether it can go in.
    case 'waiting':
    case 'arrived':
      return 'arrived';
    case 'with doctor':
    case 'in consultation':
      return 'in_consultation';
    default:
      return null;
  }
}

/// Reads one row of a visits file. [doctors] maps each doctor name as the
/// file writes it (cleaned) to the roster doctor it was matched to.
export function readVisitRow(
  cells: readonly string[],
  columns: readonly (VisitColumn | null)[],
  row: number,
  doctors: ReadonlyMap<string, string>,
  dateOrder: DateOrder = 'month_first',
): ImportRow {
  const errors: string[] = [];
  const v = cellsByColumn(cells, columns);
  const json: Record<string, any> = {
    row,
    ...readPatientRef({
      patientId: v.get(VisitColumn.patientId),
      chartNumber: v.get(VisitColumn.chartNumber),
      name: v.get(VisitColumn.patientName),
      phone: v.get(VisitColumn.patientPhone),
    }),
  };
  if (!('patient_id' in json) && !('chart_number' in json) && !('patient_name' in json)) {
    errors.push('No patient: give a chart number or a name.');
  }
  const birthday = v.get(VisitColumn.patientBirthday);
  if (birthday != null) {
    const d = parseImportDate(birthday, dateOrder);
    if (d == null) errors.push(`Birthday "${birthday}" is not a date.`);
    else json.patient_birthday = isoDate(d);
  }

  const date = v.get(VisitColumn.date);
  if (date == null) errors.push('No date.');
  else {
    const d = parseImportDate(date, dateOrder);
    if (d == null) errors.push(`Date "${date}" is not a date.`);
    else json.date = isoDate(d);
  }
  const time = v.get(VisitColumn.time);
  if (time != null) {
    const t = parseImportTime(time);
    if (t == null) errors.push(`Time "${time}" is not a time.`);
    else json.time = t;
  }

  const doctor = v.get(VisitColumn.doctor) ?? '';
  const doctorId = doctors.get(doctor);
  if (doctorId != null) json.doctor_id = doctorId;
  else errors.push(doctor === '' ? 'No doctor: pick one for the rows without a name.' : `Doctor "${doctor}" is not matched to anyone on the roster.`);

  const service = v.get(VisitColumn.service);
  if (service != null) json.service = service;
  const duration = v.get(VisitColumn.duration);
  if (duration != null) {
    const digits = duration.replace(/[^0-9]/g, '');
    const m = digits === '' ? null : Number(digits);
    if (m == null || m < 5 || m > 480) errors.push(`Minutes "${duration}" is not between 5 and 480.`);
    else json.duration_minutes = m;
  }
  const status = v.get(VisitColumn.status);
  if (status != null) {
    const s = parseVisitStatus(status);
    if (s == null) errors.push(`Status "${status}" is not Completed, Cancelled, No-show, Pending or Confirmed.`);
    else json.status = s;
  }
  const visitNote = v.get(VisitColumn.visitNote);
  if (visitNote != null) json.visit_note = visitNote;
  const patientNote = v.get(VisitColumn.patientNote);
  if (patientNote != null) json.patient_note = patientNote;

  const name = [json.patient_name ?? json.chart_number ?? 'Patient', json.date].filter((s): s is string => typeof s === 'string').join(' · ');
  return new ImportRow(row, json, name, errors, [], cells);
}

/// One export_visits row as the cells of [columns].
export function exportVisitCells(v: Record<string, any>, columns: readonly VisitColumn[]): string[] {
  return columns.map((c) => {
    if (c === VisitColumn.status) {
      const s = appointmentStatuses.find((x) => x === v.status);
      return s != null ? statusMeta[s].label : `${v.status ?? ''}`;
    }
    return v[c.key] == null ? '' : String(v[c.key]);
  });
}
