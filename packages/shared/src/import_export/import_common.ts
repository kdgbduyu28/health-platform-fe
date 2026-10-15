import { isValid, parse } from 'date-fns';

import { formatDay } from '../util/dates';
import { unescapeCell } from './csv';

/// What every kind of file (patients, visits, dental chart) shares: its
/// columns, how a header is recognised, how a row comes out, and reading
/// cells as clinics type them.

/// One column a file can have.
export interface ImportColumn {
  /// The key in the import function's row JSON and the export's output.
  readonly key: string;
  /// The header an exported file and the template carry.
  readonly header: string;
  /// Other headers clinics use for it.
  readonly aliases: readonly string[];
  /// What goes in it, for the column picker.
  readonly hint: string;
  /// Read-only facts an export adds; an import ignores them.
  readonly exportOnly: boolean;
}

/// Each of [headers]' columns as the one of [columns] it most likely holds,
/// or none. A column is used at most once: the first header that names it.
export function matchColumns<T extends ImportColumn>(headers: readonly string[], columns: readonly T[]): (T | null)[] {
  const used = new Set<T>();
  return headers.map((h) => {
    const n = normHeader(h);
    for (const c of columns) {
      if (c.exportOnly || used.has(c)) continue;
      if (normHeader(c.header) === n || normHeader(c.key) === n || c.aliases.some((a) => normHeader(a) === n)) {
        used.add(c);
        return c;
      }
    }
    return null;
  });
}

/// "Mobile No." and "mobile_no" are the same header.
export function normHeader(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/// One row of a file, read: the JSON an import function takes, or why not.
export class ImportRow {
  readonly errors: string[];

  constructor(
    /// Its line in the file (the header is 1).
    readonly row: number,
    readonly json: Record<string, any>,
    /// Who the row is about, to list it by.
    readonly name: string,
    /// What stops it being imported. Checked here, before the database
    /// sees it.
    errors: string[] = [],
    readonly warnings: string[] = [],
    /// The row as it was in the file, for the "rows that failed" download.
    readonly cells: readonly string[] = [],
  ) {
    this.errors = errors;
  }

  get ok(): boolean {
    return this.errors.length === 0;
  }
}

/// How a file writes dates such as 03/04/1990. An ISO date (1990-04-03) and
/// a written-out one (April 3, 1990) read the same either way.
export type DateOrder = 'month_first' | 'day_first';
export const dateOrderLabel: Record<DateOrder, string> = {
  month_first: 'Month first (03/04/1990 is March 4)',
  day_first: 'Day first (03/04/1990 is 3 April)',
};

/// Placeholders that mean "nothing written here".
export const blankWords = new Set(['-', '--', 'n/a', 'na', 'none', 'wala', 'nil', 'null']);

/// A cell trimmed, one space between words, and empty for a placeholder.
export function cleanCell(raw: string): string {
  const s = unescapeCell(raw.trim()).replace(/\s+/g, ' ');
  return blankWords.has(s.toLowerCase()) ? '' : s;
}

export function isoDate(d: Date): string {
  return formatDay(d);
}

/// "Juan dela Cruz, Jr." is not "Jr. Juan dela Cruz".
const suffixes = new Set(['jr', 'sr', 'ii', 'iii', 'iv', 'v']);

/// "JUAN DELA CRUZ" and "Dela Cruz, Juan" as "Juan Dela Cruz". A name typed
/// in mixed case is left as typed.
export function tidyName(name: string): string {
  let n = name.trim().replace(/\s+/g, ' ');
  const parts = n.split(',');
  if (parts.length === 2 && parts[0].trim() !== '' && parts[1].trim() !== '' && !suffixes.has(normHeader(parts[1]))) {
    n = `${parts[1].trim()} ${parts[0].trim()}`;
  }
  if (n === n.toUpperCase() && n !== n.toLowerCase()) {
    n = n.toLowerCase().replace(/\p{L}+/gu, (w) => w[0].toUpperCase() + w.substring(1));
  }
  return n;
}

const written = ['MMMM d, y', 'MMM d, y', 'MMM. d, y', 'd MMMM y', 'd MMM y', 'd-MMM-y'];

/// A date as clinics write them; null if it is not one.
export function parseImportDate(raw: string, order: DateOrder, now: Date = new Date()): Date | null {
  const s = raw.trim();
  // ISO, with or without a time after it.
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})/.exec(s);
  if (iso) return dateOf(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const slashed = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2}|\d{4})$/.exec(s);
  if (slashed) {
    const a = Number(slashed[1]);
    const b = Number(slashed[2]);
    let y = Number(slashed[3]);
    if (slashed[3].length === 2) {
      // 90 is 1990, 05 is 2005: never a year still to come.
      y += 2000;
      if (y > now.getFullYear()) y -= 100;
    }
    return order === 'month_first' ? dateOf(y, a, b) : dateOf(y, b, a);
  }
  for (const f of written) {
    const d = parse(s, f, now);
    if (isValid(d) && d.getFullYear() >= 1000) return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }
  return null;
}

function dateOf(y: number, m: number, d: number): Date | null {
  if (y < 1900 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const date = new Date(y, m - 1, d);
  // Dates roll 31 April over into May; a real date does not.
  return date.getMonth() === m - 1 && date.getDate() === d ? date : null;
}

/// A time of day as "HH:MM": "9:00", "9.30", "2 PM", "2:30pm", "14:30".
/// Null if it is not one.
export function parseImportTime(raw: string): string | null {
  const m = /^(\d{1,2})(?:[:.](\d{2}))?(?::\d{2})?\s*([ap])?\.?\s*m?\.?$/i.exec(raw.trim());
  if (!m) return null;
  let h = Number(m[1]);
  const min = Number(m[2] ?? '0');
  const half = m[3]?.toLowerCase();
  // A bare "9" is a number, not a time.
  if (m[2] == null && half == null) return null;
  if (half != null) {
    if (h < 1 || h > 12) return null;
    h = (h % 12) + (half === 'p' ? 12 : 0);
  }
  if (h > 23 || min > 59) return null;
  return `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
}

/// Yes/No as clinics answer it, English or Filipino. Null: not an answer.
export function parseYesNo(raw: string): boolean | null {
  switch (raw.trim().toLowerCase()) {
    case 'yes':
    case 'y':
    case 'true':
    case '1':
    case 'oo':
    case 'opo':
    case '✓':
    case 'x':
      return true;
    case 'no':
    case 'n':
    case 'false':
    case '0':
    case 'hindi':
    case 'di':
      return false;
    default:
      return null;
  }
}

/// "₱1,500.50", "PHP 1500", "1500" — pesos, as a number.
export function parsePesos(raw: string): number | null {
  const s = raw.replace(/php|₱|p|,|\s/gi, '');
  if (s === '' || !/^[+-]?(\d+\.?\d*|\.\d+)$/.test(s)) return null;
  return Number(s);
}

/// The patient a visit or chart row is about, as the import functions find
/// them (`private.import_find_patient`): chart id, chart number, or a name
/// with a phone or birthday to tell namesakes apart.
export function readPatientRef(r: {
  patientId?: string;
  chartNumber?: string;
  name?: string;
  phone?: string;
  birthday?: string;
}): Record<string, string> {
  return {
    ...(r.patientId != null ? { patient_id: r.patientId } : {}),
    ...(r.chartNumber != null ? { chart_number: r.chartNumber } : {}),
    ...(r.name != null ? { patient_name: tidyName(r.name) } : {}),
    ...(r.phone != null ? { patient_phone: r.phone } : {}),
    ...(r.birthday != null ? { patient_birthday: r.birthday } : {}),
  };
}

/// Cleaned cells of a row by the column each is, the empty ones left out.
export function cellsByColumn<T>(cells: readonly string[], columns: readonly (T | null)[], skip?: (c: T) => boolean): Map<T, string> {
  const v = new Map<T, string>();
  for (let i = 0; i < columns.length && i < cells.length; i++) {
    const c = columns[i];
    if (c == null || skip?.(c)) continue;
    const s = cleanCell(cells[i]);
    if (s !== '') v.set(c, s);
  }
  return v;
}
