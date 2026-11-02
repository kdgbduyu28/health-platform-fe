import { parseTime, parseTimeOrNull } from '../util/dates';

type Json = Record<string, any>;

/// One medicine on a prescription. [drug] is the generic name, which the
/// Generics Act (RA 6675) wants on every prescription; [sig] the
/// instructions.
export type RxItem = {
  drug: string;
  brand?: string | null;
  strength?: string | null;
  form?: string | null;
  quantity?: number | null;
  sig: string;
};

/// The most a prescription holds, as the database checks it.
export const maxRxItems = 20;

/// `Amoxicillin (Amoxil) 500 mg capsule` — the medicine as a pharmacist
/// reads it, without the count or the instructions.
export function rxItemTitle(i: RxItem): string {
  const brand = i.brand?.trim() ? ` (${i.brand.trim()})` : '';
  return [`${i.drug.trim()}${brand}`, i.strength?.trim(), i.form?.trim()].filter((s) => !!s).join(' ');
}

/// What is wrong with [i], or null when the database will take it.
export function rxItemProblem(i: RxItem): string | null {
  if (i.drug.trim() === '') return 'Give the generic name.';
  if (i.sig.trim() === '') return 'Say how to take it.';
  if (i.quantity != null && (!Number.isInteger(i.quantity) || i.quantity < 1 || i.quantity > 9999)) return 'The quantity is a whole number from 1 to 9999.';
  return null;
}

/// [i] as the database stores it: trimmed, blanks left out.
export function rxItemToJson(i: RxItem): Json {
  const out: Json = { drug: i.drug.trim(), sig: i.sig.trim() };
  for (const k of ['brand', 'strength', 'form'] as const) {
    const v = i[k]?.trim();
    if (v) out[k] = v;
  }
  if (i.quantity != null) out.quantity = i.quantity;
  return out;
}

/// A prescription from `public.prescriptions`, with its doctor — see
/// 20261102120100_prescriptions in health-platform-be. Never changes once
/// written; a mistake is voided and a new one written.
export class Prescription {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly patientId: string,
    readonly appointmentId: string | null,
    readonly doctorId: string,
    readonly items: RxItem[],
    readonly notes: string | null,
    readonly issuedAt: Date,
    readonly doctorName: string,
    readonly prcLicenseNo: string | null = null,
    readonly ptrNo: string | null = null,
    readonly s2LicenseNo: string | null = null,
    readonly voidedAt: Date | null = null,
    readonly voidReason: string | null = null,
  ) {}

  get isVoid(): boolean {
    return this.voidedAt != null;
  }

  /// The columns to select: the row and its doctor's name and licences.
  static readonly select = '*, doctor:doctors(full_name, prc_license_no, ptr_no, s2_license_no)';

  static fromJson(json: Json): Prescription {
    const d = (json.doctor as Json | null) ?? {};
    return new Prescription(
      json.id,
      json.clinic_id,
      json.patient_id,
      json.appointment_id ?? null,
      json.doctor_id,
      ((json.items as Json[] | null) ?? []).map((i) => ({
        drug: String(i.drug ?? ''),
        brand: i.brand ?? null,
        strength: i.strength ?? null,
        form: i.form ?? null,
        quantity: i.quantity == null ? null : Number(i.quantity),
        sig: String(i.sig ?? ''),
      })),
      json.notes ?? null,
      parseTime(json.issued_at),
      d.full_name ?? 'Doctor',
      d.prc_license_no ?? null,
      d.ptr_no ?? null,
      d.s2_license_no ?? null,
      parseTimeOrNull(json.voided_at),
      json.void_reason ?? null,
    );
  }
}
