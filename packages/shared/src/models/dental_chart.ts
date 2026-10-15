import type { IconName } from '../theme/icons';
import { parseTimeOrNull } from '../util/dates';

type Json = Record<string, any>;

/// The dental chart (odontogram), as the database keeps it: a log of
/// DentalEntry rows in `dental_chart_entries`, one per thing known about one
/// tooth. What each tooth looks like today is derived from that log by
/// DentalChart, never stored — so the picture and the history cannot
/// disagree.
///
/// Teeth are numbered FDI (ISO 3950) everywhere in data: quadrant then
/// position, 11–48 permanent, 51–85 primary. ToothNumbering converts for
/// display.

/// A tooth surface. On the chart, `B` (buccal) faces the outside of the arch
/// and `M` (mesial) faces the midline. The value is the wire letter.
export type ToothSurface = 'M' | 'O' | 'D' | 'B' | 'L';
export const toothSurfaces: readonly ToothSurface[] = ['M', 'O', 'D', 'B', 'L'];
export const toothSurfaceLabel: Record<ToothSurface, string> = {
  M: 'Mesial',
  O: 'Occlusal',
  D: 'Distal',
  B: 'Buccal',
  L: 'Lingual',
};

export function toothSurfaceFromWire(value: string): ToothSurface {
  if ((toothSurfaces as readonly string[]).includes(value)) return value as ToothSurface;
  throw new Error(`unknown tooth surface: ${value}`);
}

/// Front teeth have an incisal edge and a facial side rather than an occlusal
/// surface and a buccal one; same surface, the name dentists use.
export function surfaceLabelFor(surface: ToothSurface, tooth: number): string {
  const q = Math.floor(tooth / 10);
  if (surface === 'O' && isAnterior(tooth)) return 'Incisal';
  if (surface === 'B' && isAnterior(tooth)) return 'Facial';
  if (surface === 'L' && (q === 1 || q === 2 || q === 5 || q === 6)) return 'Palatal';
  return toothSurfaceLabel[surface];
}

/// What an entry records. Conditions are findings; the rest are treatments.
export type DentalCode =
  | 'caries'
  | 'fracture'
  | 'missing'
  | 'impacted'
  | 'watch'
  | 'filling'
  | 'sealant'
  | 'veneer'
  | 'crown'
  | 'bridge'
  | 'root_canal'
  | 'implant'
  | 'extraction';

export const dentalCodes: readonly DentalCode[] = [
  'caries',
  'fracture',
  'missing',
  'impacted',
  'watch',
  'filling',
  'sealant',
  'veneer',
  'crown',
  'bridge',
  'root_canal',
  'implant',
  'extraction',
];

type DentalCodeInfo = {
  label: string;
  abbreviation: string;
  /// A finding (always `existing`), not a treatment.
  isCondition: boolean;
  /// Recorded on particular surfaces rather than the whole tooth.
  usesSurfaces: boolean;
  /// The chart colour: problems warm, restorations cool, gone grey.
  color: string;
  icon: IconName;
  /// How a patient reads it, where the clinical word would puzzle them.
  patientLabel: string;
};

const c = (
  label: string,
  abbreviation: string,
  color: string,
  icon: IconName,
  opts: { isCondition?: boolean; usesSurfaces?: boolean; patientLabel?: string } = {},
): DentalCodeInfo => ({
  label,
  abbreviation,
  color,
  icon,
  isCondition: opts.isCondition ?? false,
  usesSurfaces: opts.usesSurfaces ?? false,
  patientLabel: opts.patientLabel ?? label,
});

export const dentalCodeMeta: Record<DentalCode, DentalCodeInfo> = {
  caries: c('Decay', 'Car', '#D32F2F', 'coronavirus', { isCondition: true, usesSurfaces: true, patientLabel: 'Cavity' }),
  fracture: c('Fracture', 'Fx', '#E64A19', 'flash-on', { isCondition: true, usesSurfaces: true }),
  missing: c('Missing', 'M', '#757575', 'remove-circle-outline', { isCondition: true }),
  impacted: c('Impacted', 'Imp', '#8D6E63', 'vertical-align-bottom', { isCondition: true }),
  watch: c('Watch', 'W', '#F9A825', 'visibility', { isCondition: true, patientLabel: 'Being monitored' }),
  filling: c('Filling', 'F', '#1E88E5', 'format-color-fill', { usesSurfaces: true }),
  sealant: c('Sealant', 'S', '#00897B', 'shield', { usesSurfaces: true }),
  veneer: c('Veneer', 'V', '#5E35B1', 'layers', { usesSurfaces: true }),
  crown: c('Crown', 'Cr', '#C49000', 'emoji-events'),
  bridge: c('Bridge', 'Br', '#6D4C41', 'linear-scale'),
  root_canal: c('Root canal', 'RCT', '#AD1457', 'timeline', { patientLabel: 'Root canal treatment' }),
  implant: c('Implant', 'Imp', '#455A64', 'hardware'),
  extraction: c('Extraction', 'X', '#757575', 'content-cut'),
};

export function dentalCodeFromWire(value: string): DentalCode {
  if ((dentalCodes as readonly string[]).includes(value)) return value as DentalCode;
  throw new Error(`unknown dental code: ${value}`);
}

export type DentalEntryStatus = 'existing' | 'planned' | 'done';
export const dentalEntryStatuses: readonly DentalEntryStatus[] = ['existing', 'planned', 'done'];
/// `existing`: found on examination — a condition, or work done before
/// (anywhere). `planned`: the treatment plan, to be done at a later visit.
/// `done`: performed at the entry's visit.
export const dentalEntryStatusLabel: Record<DentalEntryStatus, string> = {
  existing: 'On exam',
  planned: 'Planned',
  done: 'Done',
};

export function dentalEntryStatusFromWire(value: string): DentalEntryStatus {
  if ((dentalEntryStatuses as readonly string[]).includes(value)) return value as DentalEntryStatus;
  throw new Error(`unknown dental entry status: ${value}`);
}

/// The statuses the database accepts for this code.
export function allowedStatuses(code: DentalCode): readonly DentalEntryStatus[] {
  if (dentalCodeMeta[code].isCondition) return ['existing'];
  if (code === 'extraction') return ['planned', 'done'];
  return dentalEntryStatuses;
}

/// How tooth numbers are shown. Storage is always FDI.
///
/// `fdi`: two digits, quadrant then position — 11–48, primary 51–85.
/// `universal`: 1–32 from the upper right around to the lower right; primary
/// A–T.
export type ToothNumbering = 'fdi' | 'universal';
export const toothNumberingLabel: Record<ToothNumbering, string> = { fdi: 'FDI', universal: 'Universal' };

export function toothNumberingFromWire(value: string | null | undefined): ToothNumbering {
  return value === 'universal' ? 'universal' : 'fdi';
}

/// The FDI tooth number as [numbering] writes it.
export function toothLabel(numbering: ToothNumbering, fdi: number): string {
  return numbering === 'fdi' ? `${fdi}` : universalLabel(fdi);
}

/// `MOD`: surfaces in the conventional order.
export function surfacesLabel(surfaces: Iterable<ToothSurface>): string {
  const set = new Set(surfaces);
  return toothSurfaces.filter((s) => set.has(s)).join('');
}

/// One row of `dental_chart_entries`, or of `patient_dental_chart()` — which
/// is the same row without [note].
export class DentalEntry {
  constructor(
    readonly id: string,
    /// FDI number.
    readonly tooth: number,
    readonly code: DentalCode,
    readonly status: DentalEntryStatus,
    readonly surfaces: Set<ToothSurface> = new Set(),
    /// The visit it was found, planned or done at. Null for what was charted
    /// outside a visit.
    readonly appointmentId: string | null = null,
    /// A short technical detail. Never present for a patient: their function
    /// leaves it out.
    readonly note: string | null = null,
    readonly createdAt: Date | null = null,
    readonly updatedAt: Date | null = null,
  ) {}

  static fromJson(json: Json): DentalEntry {
    return new DentalEntry(
      json.id,
      json.tooth,
      dentalCodeFromWire(json.code),
      dentalEntryStatusFromWire(json.status),
      new Set(((json.surfaces ?? []) as string[]).map(toothSurfaceFromWire)),
      json.appointment_id ?? null,
      json.note ?? null,
      parseTimeOrNull(json.created_at),
      parseTimeOrNull(json.updated_at),
    );
  }

  /// `Filling 46 · MO`, in the given numbering.
  describe(numbering: ToothNumbering, { forPatient = false }: { forPatient?: boolean } = {}): string {
    const meta = dentalCodeMeta[this.code];
    const name = forPatient ? meta.patientLabel : meta.label;
    const where = this.surfaces.size === 0 ? '' : ` · ${surfacesLabel(this.surfaces)}`;
    return `${name} ${toothLabel(numbering, this.tooth)}${where}`;
  }
}

// ── Numbering ───────────────────────────────────────────────────────────────

/// FDI → Universal: `18` → `1`, `48` → `32`, `55` → `A`, `85` → `T`.
export function universalLabel(fdi: number): string {
  const q = Math.floor(fdi / 10);
  const p = fdi % 10;
  if (q <= 4) {
    const n = q === 1 ? 9 - p : q === 2 ? 8 + p : q === 3 ? 25 - p : 24 + p;
    return `${n}`;
  }
  const i = q === 5 ? 5 - p : q === 6 ? 4 + p : q === 7 ? 15 - p : 14 + p;
  return String.fromCharCode('A'.charCodeAt(0) + i);
}

/// Incisors and canines.
export function isAnterior(fdi: number): boolean {
  return fdi % 10 <= 3;
}

export function isPrimary(fdi: number): boolean {
  return Math.floor(fdi / 10) >= 5;
}

/// `Lower left first molar`.
export function toothName(fdi: number): string {
  const q = Math.floor(fdi / 10);
  const p = fdi % 10;
  const jaw = q === 1 || q === 2 || q === 5 || q === 6 ? 'Upper' : 'Lower';
  const side = q === 1 || q === 4 || q === 5 || q === 8 ? 'right' : 'left';
  const kind = isPrimary(fdi)
    ? ['central incisor', 'lateral incisor', 'canine', 'first molar', 'second molar'][p - 1]
    : [
        'central incisor',
        'lateral incisor',
        'canine',
        'first premolar',
        'second premolar',
        'first molar',
        'second molar',
        'third molar',
      ][p - 1];
  return `${jaw} ${side} ${isPrimary(fdi) ? 'baby ' : ''}${kind}`;
}

/// The teeth of one dentition, laid out as the chart draws them: the upper
/// arch left to right as seen facing the patient (their right first), then
/// the lower arch the same way.
export type Dentition = 'permanent' | 'primary';
export const dentitionLabel: Record<Dentition, string> = { permanent: 'Adult', primary: 'Child' };

export function upperTeeth(d: Dentition): number[] {
  return d === 'permanent'
    ? [18, 17, 16, 15, 14, 13, 12, 11, 21, 22, 23, 24, 25, 26, 27, 28]
    : [55, 54, 53, 52, 51, 61, 62, 63, 64, 65];
}

export function lowerTeeth(d: Dentition): number[] {
  return d === 'permanent'
    ? [48, 47, 46, 45, 44, 43, 42, 41, 31, 32, 33, 34, 35, 36, 37, 38]
    : [85, 84, 83, 82, 81, 71, 72, 73, 74, 75];
}

/// Children under 12 are charted on their baby teeth by default.
export function dentitionForAge(age: number | null): Dentition {
  return age != null && age < 12 ? 'primary' : 'permanent';
}

// ── The chart ───────────────────────────────────────────────────────────────

/// One tooth as the chart shows it now.
export class ToothState {
  /// Gone: found missing or extracted, and not since replaced by an implant.
  missing = false;
  /// What is on each surface now: decay, or what repaired it.
  readonly surfaces = new Map<ToothSurface, DentalCode>();
  /// Whole-tooth findings and restorations present now.
  readonly whole = new Set<DentalCode>();
  /// Work still to be done on this tooth.
  readonly planned: DentalEntry[] = [];
  /// Everything ever recorded on this tooth, oldest first.
  readonly history: DentalEntry[] = [];

  constructor(readonly tooth: number) {}

  get isEmpty(): boolean {
    return this.history.length === 0;
  }

  get hasProblem(): boolean {
    for (const code of this.surfaces.values()) if (dentalCodeMeta[code].isCondition) return true;
    for (const code of this.whole) if (dentalCodeMeta[code].isCondition && code !== 'missing') return true;
    return false;
  }

  /// The single most telling code, for a compact marker.
  get headline(): DentalCode | null {
    if (this.missing) return 'missing';
    for (const code of ['implant', 'crown', 'bridge', 'root_canal', 'impacted', 'fracture', 'caries', 'veneer', 'watch'] as const) {
      if (this.whole.has(code)) return code;
    }
    return null;
  }
}

/// A patient's chart: DentalEntry rows folded into a ToothState per tooth.
///
/// Entries apply in the order they were recorded. A later filling on a surface
/// replaces the decay under it; an extraction (or a tooth found missing)
/// clears everything on the tooth, and a later implant brings it back. Planned
/// work changes nothing until it is done.
export class DentalChart {
  private readonly teeth = new Map<number, ToothState>();

  /// Every entry, oldest first.
  readonly entries: readonly DentalEntry[];

  constructor(entries: readonly DentalEntry[]) {
    // Stable, like Dart's List.sort on equal keys in practice; entries
    // without a time keep their place.
    const ordered = [...entries].sort((a, b) => {
      if (a.createdAt == null || b.createdAt == null) return 0;
      return a.createdAt.getTime() - b.createdAt.getTime();
    });
    for (const e of ordered) {
      let t = this.teeth.get(e.tooth);
      if (!t) {
        t = new ToothState(e.tooth);
        this.teeth.set(e.tooth, t);
      }
      t.history.push(e);
      if (e.status === 'planned') {
        t.planned.push(e);
        continue;
      }
      DentalChart.apply(t, e);
    }
    this.entries = Object.freeze(ordered);
  }

  stateOf(tooth: number): ToothState {
    return this.teeth.get(tooth) ?? new ToothState(tooth);
  }

  get isEmpty(): boolean {
    return this.teeth.size === 0;
  }

  /// Outstanding work, tooth by tooth.
  get plan(): DentalEntry[] {
    return [...this.teeth.values()].sort((a, b) => a.tooth - b.tooth).flatMap((t) => t.planned);
  }

  /// What was recorded at one visit, in chart order.
  atVisit(appointmentId: string): DentalEntry[] {
    return this.entries.filter((e) => e.appointmentId === appointmentId).sort((a, b) => a.tooth - b.tooth);
  }

  /// Whether any primary tooth has been charted, so the chart can open on the
  /// dentition the patient actually has.
  get hasPrimaryTeeth(): boolean {
    return [...this.teeth.keys()].some(isPrimary);
  }

  get hasPermanentTeeth(): boolean {
    return [...this.teeth.keys()].some((t) => !isPrimary(t));
  }

  private static apply(t: ToothState, e: DentalEntry): void {
    switch (e.code) {
      case 'missing':
      case 'extraction':
        t.missing = true;
        t.surfaces.clear();
        t.whole.clear();
        return;
      case 'implant':
        t.missing = false;
        t.surfaces.clear();
        t.whole.clear();
        t.whole.add('implant');
        return;
      case 'crown':
        // A crown covers every surface.
        t.surfaces.clear();
        t.whole.delete('caries');
        t.whole.delete('fracture');
        t.whole.add('crown');
        return;
      case 'filling':
      case 'sealant':
      case 'veneer':
      case 'caries':
      case 'fracture':
        if (e.surfaces.size === 0) {
          t.whole.add(e.code);
        } else {
          for (const s of e.surfaces) t.surfaces.set(s, e.code);
          // Repairing the tooth resolves whole-tooth decay recorded before.
          if (!dentalCodeMeta[e.code].isCondition) {
            t.whole.delete('caries');
            t.whole.delete('fracture');
          }
        }
        return;
      case 'root_canal':
        t.whole.add('root_canal');
        t.whole.delete('caries');
        return;
      case 'bridge':
      case 'impacted':
      case 'watch':
        t.whole.add(e.code);
        return;
    }
  }
}

/// `Filling on MO; crown; 1 planned`. What a screen reader says for a tooth.
export function describeTooth(t: ToothState): string {
  if (t.isEmpty) return 'Nothing recorded';
  const parts: string[] = [];
  if (t.missing) parts.push('missing');
  for (const c of t.whole) parts.push(dentalCodeMeta[c].label.toLowerCase());
  const bySurface = new Map<DentalCode, ToothSurface[]>();
  for (const [s, c] of t.surfaces) {
    const list = bySurface.get(c) ?? [];
    list.push(s);
    bySurface.set(c, list);
  }
  for (const [c, ss] of bySurface) parts.push(`${dentalCodeMeta[c].label.toLowerCase()} on ${surfacesLabel(ss)}`);
  if (t.planned.length > 0) parts.push(`${t.planned.length} planned`);
  return parts.length === 0 ? 'Healthy' : parts.join('; ');
}
