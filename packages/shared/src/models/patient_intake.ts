import { parseTime } from '../util/dates';

type Json = Record<string, any>;

/// Mirrors `patient_intakes.guardian_relationship`.
export type GuardianRelationship = 'parent' | 'guardian';
export const guardianRelationships: readonly GuardianRelationship[] = ['parent', 'guardian'];
export const guardianRelationshipLabel: Record<GuardianRelationship, string> = {
  parent: 'Parent',
  guardian: 'Guardian',
};
export function guardianRelationshipFromWire(wire: string | null | undefined): GuardianRelationship {
  return wire === 'parent' ? 'parent' : 'guardian';
}

/// Who typed the form in.
export type IntakeSource = 'patient_app' | 'front_desk_tablet' | 'staff' | 'import';
/// Completes "Filled in …".
export const intakeSourceDescription: Record<IntakeSource, string> = {
  patient_app: 'by the patient, in the app',
  front_desk_tablet: 'by the patient, on the front desk tablet',
  staff: 'by the front desk',
  import: 'from an imported file',
};
export function intakeSourceFromWire(wire: string): IntakeSource {
  return wire in intakeSourceDescription ? (wire as IntakeSource) : 'staff';
}

/// Mirrors `private.intake_allergies()`.
export type IntakeAllergy =
  | 'local_anesthetic'
  | 'penicillin'
  | 'other_antibiotics'
  | 'sulfa'
  | 'aspirin'
  | 'latex';
export const intakeAllergies: readonly IntakeAllergy[] = [
  'local_anesthetic',
  'penicillin',
  'other_antibiotics',
  'sulfa',
  'aspirin',
  'latex',
];
export const intakeAllergyLabel: Record<IntakeAllergy, string> = {
  local_anesthetic: 'Local anesthetic (e.g. lidocaine)',
  penicillin: 'Penicillin',
  other_antibiotics: 'Other antibiotics',
  sulfa: 'Sulfa drugs',
  aspirin: 'Aspirin',
  latex: 'Latex',
};

/// Mirrors `private.intake_conditions()`.
export type IntakeCondition =
  | 'high_blood_pressure'
  | 'low_blood_pressure'
  | 'heart_disease'
  | 'diabetes'
  | 'asthma'
  | 'bleeding_disorder'
  | 'anemia'
  | 'hepatitis'
  | 'kidney_disease'
  | 'thyroid_problem'
  | 'epilepsy'
  | 'stroke'
  | 'cancer'
  | 'tuberculosis';
export const intakeConditions: readonly IntakeCondition[] = [
  'high_blood_pressure',
  'low_blood_pressure',
  'heart_disease',
  'diabetes',
  'asthma',
  'bleeding_disorder',
  'anemia',
  'hepatitis',
  'kidney_disease',
  'thyroid_problem',
  'epilepsy',
  'stroke',
  'cancer',
  'tuberculosis',
];
export const intakeConditionLabel: Record<IntakeCondition, string> = {
  high_blood_pressure: 'High blood pressure',
  low_blood_pressure: 'Low blood pressure',
  heart_disease: 'Heart disease',
  diabetes: 'Diabetes',
  asthma: 'Asthma',
  bleeding_disorder: 'Bleeding problems',
  anemia: 'Anemia',
  hepatitis: 'Hepatitis / liver disease',
  kidney_disease: 'Kidney disease',
  thyroid_problem: 'Thyroid problem',
  epilepsy: 'Epilepsy / seizures',
  stroke: 'Stroke',
  cancer: 'Cancer',
  tuberculosis: 'Tuberculosis',
};

/// Mirrors `persons.sex`.
export type Sex = 'female' | 'male';
export const sexes: readonly Sex[] = ['female', 'male'];
export const sexLabel: Record<Sex, string> = { female: 'Female', male: 'Male' };
export function sexFromWire(wire: string | null | undefined): Sex | null {
  return wire === 'female' || wire === 'male' ? wire : null;
}

/// Values this build does not know (a newer checklist) are skipped rather
/// than failing the whole form.
function wireSet<T extends string>(value: unknown, known: readonly T[]): Set<T> {
  const out = new Set<T>();
  for (const w of (value as string[] | null | undefined) ?? []) {
    if ((known as readonly string[]).includes(w)) out.add(w as T);
  }
  return out;
}

/// A parent or guardian who filled in the form for the patient: a child, or
/// an adult who cannot answer for themself. Recorded per form, not on the
/// person, so a grown-up patient's own next form drops it.
export class IntakeGuardian {
  constructor(
    readonly name: string,
    readonly relationship: GuardianRelationship,
    readonly phone: string,
    readonly email: string | null = null,
  ) {}

  /// From the intake row's guardian_* columns; null when there is none.
  static fromJson(json: Json): IntakeGuardian | null {
    const name = json.guardian_name as string | null | undefined;
    if (name == null) return null;
    return new IntakeGuardian(
      name,
      guardianRelationshipFromWire(json.guardian_relationship),
      json.guardian_phone ?? '',
      json.guardian_email ?? null,
    );
  }
}

/// The patient information form: medical history and consent, one per chart.
/// Mirrors `public.patient_intakes` (20260927120000, guardian 20261001120000).
///
/// Who someone is — name, birthday, contact, emergency contact — is on the
/// person and shared by every clinic; see Patient. What they told THIS clinic
/// about their health is here, and no other clinic can read it.
export class PatientIntake {
  constructor(
    readonly patientId: string,
    readonly reasonForVisit: string | null,
    readonly lastDentalVisit: string | null,
    readonly physicianName: string | null,
    readonly underTreatment: boolean,
    readonly treatmentDetails: string | null,
    readonly takesMedications: boolean,
    readonly medications: string | null,
    readonly allergies: Set<IntakeAllergy>,
    readonly allergiesOther: string | null,
    readonly conditions: Set<IntakeCondition>,
    readonly conditionsOther: string | null,
    /// Null when not asked (only women are).
    readonly pregnant: boolean | null,
    readonly nursing: boolean | null,
    readonly birthControl: boolean | null,
    /// Who answered for the patient, when it was not the patient themself.
    readonly guardian: IntakeGuardian | null,
    readonly consentAt: Date,
    readonly signedName: string,
    readonly source: IntakeSource,
    readonly updatedAt: Date,
  ) {}

  get hasAllergies(): boolean {
    return this.allergies.size > 0 || this.allergiesOther != null;
  }

  /// Every allergy as the patient would read it, the checklist first.
  get allergyLabels(): string[] {
    return [
      ...intakeAllergies.filter((a) => this.allergies.has(a)).map((a) => intakeAllergyLabel[a]),
      ...(this.allergiesOther != null ? [this.allergiesOther] : []),
    ];
  }

  get conditionLabels(): string[] {
    return [
      ...intakeConditions.filter((c) => this.conditions.has(c)).map((c) => intakeConditionLabel[c]),
      ...(this.conditionsOther != null ? [this.conditionsOther] : []),
    ];
  }

  static fromJson(json: Json): PatientIntake {
    return new PatientIntake(
      json.patient_id,
      json.reason_for_visit ?? null,
      json.last_dental_visit ?? null,
      json.physician_name ?? null,
      json.under_treatment,
      json.treatment_details ?? null,
      json.takes_medications,
      json.medications ?? null,
      wireSet(json.allergies, intakeAllergies),
      json.allergies_other ?? null,
      wireSet(json.conditions, intakeConditions),
      json.conditions_other ?? null,
      json.pregnant ?? null,
      json.nursing ?? null,
      json.birth_control ?? null,
      IntakeGuardian.fromJson(json),
      parseTime(json.consent_at),
      json.signed_name,
      intakeSourceFromWire(json.source),
      parseTime(json.updated_at),
    );
  }
}

/// A filled-in form, ready for `register_patient` / `save_patient_intake`: the
/// person's details and the intake, as the JSON the functions take.
export type IntakeSubmission = {
  person: Record<string, unknown>;
  intake: Record<string, unknown>;
};
