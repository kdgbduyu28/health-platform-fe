import {
  type DentalCode,
  type DentalEntryStatus,
  type ToothNumbering,
  dentalCodeMeta,
  dentalCodes,
  dentalEntryStatusLabel,
  dentalEntryStatuses,
  toothNumberingLabel,
  universalLabel,
} from '../models/dental_chart';
import {
  type DateOrder,
  type ImportColumn,
  ImportRow,
  cellsByColumn,
  isoDate,
  matchColumns,
  normHeader,
  parseImportDate,
  readPatientRef,
} from './import_common';

/// One column of a dental chart file, in and out: `import_dental` and
/// `export_dental` (20261004120000). One row per thing known about one
/// tooth, as the chart keeps it (DentalEntry).
///
/// Teeth are FDI in an export. An import also reads Universal numbering
/// (1–32, A–T) when the person says the file uses it.
export class DentalColumn implements ImportColumn {
  readonly exportOnly = false;

  private constructor(
    readonly key: string,
    readonly header: string,
    readonly hint: string,
    readonly aliases: readonly string[],
  ) {}

  static readonly patientId = new DentalColumn('patient_id', 'Patient ID', 'from an export', ['id']);
  static readonly chartNumber = new DentalColumn('chart_number', 'Chart no.', "the clinic's record number", [
    'chart number', 'chart', 'record no', 'record number', 'patient no', 'patient number', 'file no', 'folder no',
  ]);
  static readonly patientName = new DentalColumn('patient_name', 'Patient', "the patient's name", ['name', 'patient name', 'full name', 'pangalan']);
  static readonly patientPhone = new DentalColumn('patient_phone', 'Phone', 'tells namesakes apart', [
    'mobile', 'mobile no', 'contact', 'contact no', 'contact number',
  ]);
  static readonly patientBirthday = new DentalColumn('patient_birthday', 'Birthday', 'tells namesakes apart', ['birthdate', 'date of birth', 'dob']);
  static readonly tooth = new DentalColumn('tooth', 'Tooth', '16, 36 (FDI) or 3, A (Universal)', ['tooth no', 'tooth number', 'tooth #', 'ngipin']);
  static readonly surfaces = new DentalColumn('surfaces', 'Surfaces', 'M O D B L, as in MOD', ['surface', 'surfaces involved']);
  static readonly code = new DentalColumn('code', 'Finding / treatment', 'Decay, Filling, Crown, Extraction…', [
    'finding', 'treatment', 'procedure', 'condition', 'diagnosis', 'code', 'treatment done', 'work',
  ]);
  static readonly status = new DentalColumn('status', 'Status', 'On exam, Planned or Done', ['state']);
  static readonly date = new DentalColumn('date', 'Date', 'the visit it was found, planned or done at', ['visit date', 'date done', 'date of visit', 'petsa']);
  static readonly note = new DentalColumn('note', 'Note', 'up to 500 characters', ['notes', 'remarks', 'comment']);

  static readonly values: readonly DentalColumn[] = [
    DentalColumn.patientId, DentalColumn.chartNumber, DentalColumn.patientName, DentalColumn.patientPhone, DentalColumn.patientBirthday,
    DentalColumn.tooth, DentalColumn.surfaces, DentalColumn.code, DentalColumn.status, DentalColumn.date, DentalColumn.note,
  ];

  static match(headers: readonly string[]): (DentalColumn | null)[] {
    return matchColumns(headers, DentalColumn.values);
  }

  static get exported(): DentalColumn[] {
    return DentalColumn.values.filter((c) => c !== DentalColumn.patientPhone && c !== DentalColumn.patientBirthday);
  }

  static get template(): DentalColumn[] {
    return DentalColumn.values.filter((c) => c !== DentalColumn.patientId);
  }
}

/// Every FDI tooth: 11–18 … 41–48, then primary 51–55 … 81–85.
export const fdiTeeth: readonly number[] = [
  ...[1, 2, 3, 4].flatMap((q) => Array.from({ length: 8 }, (_, i) => q * 10 + i + 1)),
  ...[5, 6, 7, 8].flatMap((q) => Array.from({ length: 5 }, (_, i) => q * 10 + i + 1)),
];

const universal = new Map(fdiTeeth.map((t) => [universalLabel(t), t]));

/// A tooth as the file writes it, as FDI; null if it is not one. Letters
/// A–T are always Universal primary teeth.
export function parseTooth(raw: string, numbering: ToothNumbering): number | null {
  const s = raw
    .trim()
    .toUpperCase()
    .replace(/^#|^TOOTH\s*/, '');
  if (/^[A-T]$/.test(s)) return universal.get(s) ?? null;
  if (!/^[+-]?\d+$/.test(s)) return null;
  const n = Number(s);
  if (numbering === 'universal') return universal.get(`${n}`) ?? null;
  return fdiTeeth.includes(n) ? n : null;
}

const surfaceWords: Record<string, string> = {
  mesial: 'M',
  occlusal: 'O',
  incisal: 'O',
  distal: 'D',
  buccal: 'B',
  facial: 'B',
  labial: 'B',
  lingual: 'L',
  palatal: 'L',
};

/// Front teeth are charted Incisal and Facial; the same surfaces as O and B.
const surfaceLetters: Record<string, string> = { m: 'M', o: 'O', i: 'O', d: 'D', b: 'B', f: 'B', l: 'L', p: 'L' };

/// "MOD", "M, O", "mesial occlusal", "IF" (incisal, facial) as the chart's
/// five surfaces. Null if something in it is not a surface.
export function parseSurfaces(raw: string): string[] | null {
  const words = raw
    .toLowerCase()
    .split(/[\s,;/+-]+/)
    .filter((w) => w !== '');
  const out = new Set<string>();
  for (const w of words) {
    const whole = surfaceWords[w];
    if (whole != null) {
      out.add(whole);
      continue;
    }
    for (const ch of w) {
      const s = surfaceLetters[ch];
      if (s == null) return null;
      out.add(s);
    }
  }
  return ['B', 'D', 'L', 'M', 'O'].filter((s) => out.has(s));
}

const codeWords: Record<string, DentalCode> = {
  decay: 'caries', carious: 'caries', cavity: 'caries', cavities: 'caries', car: 'caries', sira: 'caries',
  fractured: 'fracture', broken: 'fracture', fx: 'fracture', chipped: 'fracture',
  absent: 'missing', m: 'missing',
  imp: 'impacted', monitor: 'watch', w: 'watch',
  filled: 'filling', restoration: 'filling', composite: 'filling', amalgam: 'filling', pasta: 'filling', f: 'filling', gic: 'filling',
  'glass ionomer': 'filling', 'temporary filling': 'filling',
  s: 'sealant', 'fissure sealant': 'sealant', 'pit and fissure sealant': 'sealant',
  v: 'veneer',
  jacket: 'crown', 'jacket crown': 'crown', cap: 'crown', cr: 'crown', pfm: 'crown', 'porcelain crown': 'crown',
  br: 'bridge', pontic: 'bridge', 'fixed bridge': 'bridge',
  rct: 'root_canal', endo: 'root_canal', 'root canal treatment': 'root_canal', 'root canal therapy': 'root_canal',
  x: 'extraction', extracted: 'extraction', exo: 'extraction', exodontia: 'extraction', extract: 'extraction', bunot: 'extraction',
  'tooth extraction': 'extraction',
};

/// What an entry records, as clinics write it (English, the chart's
/// abbreviations, and a few Filipino words). Null if it is none of them.
export function parseDentalCode(raw: string): DentalCode | null {
  const n = normHeader(raw);
  for (const c of dentalCodes) {
    if (n === normHeader(c) || n === normHeader(dentalCodeMeta[c].label)) return c;
  }
  return codeWords[n] ?? null;
}

export function parseDentalStatus(raw: string): DentalEntryStatus | null {
  switch (normHeader(raw)) {
    case 'existing':
    case 'on exam':
    case 'present':
    case 'old':
    case 'found':
      return 'existing';
    case 'planned':
    case 'plan':
    case 'to do':
    case 'todo':
    case 'for treatment':
    case 'recommended':
      return 'planned';
    case 'done':
    case 'completed':
    case 'treated':
    case 'performed':
      return 'done';
    default:
      return null;
  }
}

/// Reads one row of a dental chart file.
export function readDentalRow(
  cells: readonly string[],
  columns: readonly (DentalColumn | null)[],
  row: number,
  dateOrder: DateOrder = 'month_first',
  numbering: ToothNumbering = 'fdi',
): ImportRow {
  const errors: string[] = [];
  const v = cellsByColumn(cells, columns);
  const json: Record<string, any> = {
    row,
    ...readPatientRef({
      patientId: v.get(DentalColumn.patientId),
      chartNumber: v.get(DentalColumn.chartNumber),
      name: v.get(DentalColumn.patientName),
      phone: v.get(DentalColumn.patientPhone),
    }),
  };
  if (!('patient_id' in json) && !('chart_number' in json) && !('patient_name' in json)) {
    errors.push('No patient: give a chart number or a name.');
  }
  const birthday = v.get(DentalColumn.patientBirthday);
  if (birthday != null) {
    const d = parseImportDate(birthday, dateOrder);
    if (d == null) errors.push(`Birthday "${birthday}" is not a date.`);
    else json.patient_birthday = isoDate(d);
  }

  const tooth = v.get(DentalColumn.tooth);
  if (tooth == null) errors.push('No tooth.');
  else {
    const t = parseTooth(tooth, numbering);
    if (t == null) errors.push(`Tooth "${tooth}" is not a ${toothNumberingLabel[numbering]} tooth number.`);
    else json.tooth = t;
  }
  const code = v.get(DentalColumn.code);
  if (code == null) errors.push('No finding or treatment.');
  else {
    const c = parseDentalCode(code);
    if (c == null) errors.push(`"${code}" is not something the chart records (${dentalCodes.map((x) => dentalCodeMeta[x].label).join(', ')}).`);
    else json.code = c;
  }
  const surfaces = v.get(DentalColumn.surfaces);
  if (surfaces != null) {
    const s = parseSurfaces(surfaces);
    if (s == null) errors.push(`Surfaces "${surfaces}" are not M, O, D, B or L.`);
    else json.surfaces = s;
  }
  const status = v.get(DentalColumn.status);
  if (status != null) {
    const s = parseDentalStatus(status);
    if (s == null) errors.push(`Status "${status}" is not On exam, Planned or Done.`);
    else json.status = s;
  }
  const date = v.get(DentalColumn.date);
  if (date != null) {
    const d = parseImportDate(date, dateOrder);
    if (d == null) errors.push(`Date "${date}" is not a date.`);
    else json.date = isoDate(d);
  }
  const note = v.get(DentalColumn.note);
  if (note != null) {
    if (note.length > 500) errors.push('The note is longer than 500 characters.');
    json.note = note;
  }

  const name = [json.patient_name ?? json.chart_number ?? 'Patient', ...(json.tooth != null ? [`tooth ${json.tooth}`] : [])].join(' · ');
  return new ImportRow(row, json, name, errors, [], cells);
}

/// One export_dental row as the cells of [columns].
export function exportDentalCells(e: Record<string, any>, columns: readonly DentalColumn[]): string[] {
  return columns.map((c) => {
    if (c === DentalColumn.code) {
      const code = dentalCodes.find((d) => d === e.code);
      return code != null ? dentalCodeMeta[code].label : `${e.code ?? ''}`;
    }
    if (c === DentalColumn.status) {
      const s = dentalEntryStatuses.find((x) => x === e.status);
      return s != null ? dentalEntryStatusLabel[s] : `${e.status ?? ''}`;
    }
    return e[c.key] == null ? '' : String(e[c.key]);
  });
}
