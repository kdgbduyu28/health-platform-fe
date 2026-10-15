import {
  type GuardianRelationship,
  type IntakeAllergy,
  type IntakeCondition,
  type Sex,
  guardianRelationshipFromWire,
  guardianRelationshipLabel,
  intakeAllergies,
  intakeAllergyLabel,
  intakeConditionLabel,
  intakeConditions,
  sexFromWire,
  sexLabel,
} from '../models/patient_intake';
import {
  type DateOrder,
  type ImportColumn,
  ImportRow,
  blankWords,
  cellsByColumn,
  isoDate,
  matchColumns,
  normHeader,
  parseImportDate,
  parsePesos,
  parseYesNo,
  tidyName,
} from './import_common';

type Cell = 'text' | 'date' | 'yesNo' | 'sex' | 'allergies' | 'conditions' | 'money' | 'relationship';

/// One column of a patients file, in and out: the patient information form,
/// the clinic's chart note and a balance, as `import_patients` and
/// `export_patients` take and give them (20261003120000).
///
/// An exported file has these headers, in this order, and imports back as
/// is. A clinic's own spreadsheet rarely does, so every column also answers
/// to the names clinics tend to use ("Mobile no.", "Birthdate", "Surname").
export class PatientColumn implements ImportColumn {
  private constructor(
    readonly key: string,
    readonly header: string,
    readonly cell: Cell,
    readonly aliases: readonly string[],
    /// Parts of a name some files split up; joined into the full name.
    readonly importOnly = false,
    /// Read-only facts an export adds (what is owed, visits): they come from
    /// the clinic's records, so an import ignores them.
    readonly exportOnly = false,
  ) {}

  static readonly patientId = new PatientColumn('patient_id', 'Patient ID', 'text', ['id', 'patient uuid']);
  static readonly chartNumber = new PatientColumn('chart_number', 'Chart no.', 'text', [
    'chart number', 'chart', 'record no', 'record number', 'patient no', 'patient number', 'file no', 'file number', 'folder no', 'case no',
  ]);
  static readonly fullName = new PatientColumn('full_name', 'Name', 'text', ['full name', 'patient name', 'patient', 'complete name', 'pangalan']);
  static readonly lastName = new PatientColumn('last_name', 'Last name', 'text', ['surname', 'family name', 'apelyido'], true);
  static readonly firstName = new PatientColumn('first_name', 'First name', 'text', ['given name', 'given names'], true);
  static readonly middleName = new PatientColumn('middle_name', 'Middle name', 'text', ['middle initial', 'mi', 'm i'], true);
  static readonly phone = new PatientColumn('phone', 'Phone', 'text', [
    'mobile', 'mobile no', 'mobile number', 'cellphone', 'cellphone no', 'cell no', 'contact', 'contact no', 'contact number', 'phone number', 'telephone', 'tel no',
  ]);
  static readonly email = new PatientColumn('email', 'Email', 'text', ['email address', 'e mail']);
  static readonly dateOfBirth = new PatientColumn('date_of_birth', 'Birthday', 'date', ['birthdate', 'birth date', 'date of birth', 'dob', 'bday', 'birthday']);
  static readonly sex = new PatientColumn('sex', 'Sex', 'sex', ['gender', 'kasarian']);
  static readonly address = new PatientColumn('address', 'Address', 'text', ['home address', 'residence', 'tirahan']);
  static readonly occupation = new PatientColumn('occupation', 'Occupation', 'text', ['work', 'job', 'trabaho']);
  static readonly emergencyName = new PatientColumn('emergency_contact_name', 'Emergency contact', 'text', [
    'emergency contact name', 'in case of emergency', 'person to contact',
  ]);
  static readonly emergencyPhone = new PatientColumn('emergency_contact_phone', 'Emergency contact phone', 'text', [
    'emergency phone', 'emergency number', 'emergency contact no',
  ]);
  static readonly reasonForVisit = new PatientColumn('reason_for_visit', 'Reason for visit', 'text', [
    'reason', 'chief complaint', 'complaint', 'reason for consultation',
  ]);
  static readonly lastDentalVisit = new PatientColumn('last_dental_visit', 'Last dental visit', 'text', ['previous dental visit', 'last visit to dentist']);
  static readonly physicianName = new PatientColumn('physician_name', 'Physician', 'text', ['physician name', 'doctor', 'attending physician', 'family doctor']);
  static readonly underTreatment = new PatientColumn('under_treatment', 'Under treatment', 'yesNo', [
    'under medical treatment', 'in good health under treatment',
  ]);
  static readonly treatmentDetails = new PatientColumn('treatment_details', 'Treatment details', 'text', ['condition being treated', 'treatment']);
  static readonly takesMedications = new PatientColumn('takes_medications', 'Takes medications', 'yesNo', [
    'taking medications', 'on medication', 'taking medication',
  ]);
  static readonly medications = new PatientColumn('medications', 'Medications', 'text', ['medication', 'maintenance', 'maintenance medicines', 'medicines']);
  static readonly allergies = new PatientColumn('allergies', 'Allergies', 'allergies', ['allergy', 'allergic to']);
  static readonly allergiesOther = new PatientColumn('allergies_other', 'Other allergies', 'text', ['allergies other']);
  static readonly conditions = new PatientColumn('conditions', 'Conditions', 'conditions', ['medical conditions', 'medical history', 'illnesses', 'diseases']);
  static readonly conditionsOther = new PatientColumn('conditions_other', 'Other conditions', 'text', ['conditions other']);
  static readonly pregnant = new PatientColumn('pregnant', 'Pregnant', 'yesNo', []);
  static readonly nursing = new PatientColumn('nursing', 'Nursing', 'yesNo', ['breastfeeding']);
  static readonly birthControl = new PatientColumn('birth_control', 'Birth control', 'yesNo', ['birth control pills', 'contraceptives']);
  static readonly guardianName = new PatientColumn('guardian_name', 'Guardian', 'text', ['guardian name', 'parent', 'parent name', 'parent guardian']);
  static readonly guardianRelationship = new PatientColumn('guardian_relationship', 'Guardian relationship', 'relationship', ['relationship', 'relation']);
  static readonly guardianPhone = new PatientColumn('guardian_phone', 'Guardian phone', 'text', ['parent phone', 'guardian contact', 'guardian contact no']);
  static readonly guardianEmail = new PatientColumn('guardian_email', 'Guardian email', 'text', ['parent email']);
  static readonly signedName = new PatientColumn('signed_name', 'Signed by', 'text', ['signature', 'signed', 'signed name', 'signatory']);
  static readonly signedOn = new PatientColumn('signed_on', 'Signed on', 'date', ['date signed', 'form date', 'consent date', 'date']);
  static readonly chartNote = new PatientColumn('chart_note', 'Clinic notes', 'text', [
    'notes', 'note', 'clinical notes', 'chart notes', 'remarks', 'medical notes',
  ]);
  static readonly openingBalance = new PatientColumn('opening_balance', 'Opening balance', 'money', [
    'balance forwarded', 'previous balance', 'old balance', 'unpaid balance',
  ]);
  static readonly balance = new PatientColumn('balance', 'Balance', 'money', [], false, true);
  static readonly completedVisits = new PatientColumn('completed_visits', 'Completed visits', 'text', [], false, true);
  static readonly lastVisit = new PatientColumn('last_visit', 'Last visit', 'date', [], false, true);
  static readonly registeredOn = new PatientColumn('registered_on', 'Registered on', 'date', [], false, true);

  /// Every column, in file order.
  static readonly values: readonly PatientColumn[] = [
    PatientColumn.patientId, PatientColumn.chartNumber, PatientColumn.fullName, PatientColumn.lastName, PatientColumn.firstName,
    PatientColumn.middleName, PatientColumn.phone, PatientColumn.email, PatientColumn.dateOfBirth, PatientColumn.sex,
    PatientColumn.address, PatientColumn.occupation, PatientColumn.emergencyName, PatientColumn.emergencyPhone,
    PatientColumn.reasonForVisit, PatientColumn.lastDentalVisit, PatientColumn.physicianName, PatientColumn.underTreatment,
    PatientColumn.treatmentDetails, PatientColumn.takesMedications, PatientColumn.medications, PatientColumn.allergies,
    PatientColumn.allergiesOther, PatientColumn.conditions, PatientColumn.conditionsOther, PatientColumn.pregnant,
    PatientColumn.nursing, PatientColumn.birthControl, PatientColumn.guardianName, PatientColumn.guardianRelationship,
    PatientColumn.guardianPhone, PatientColumn.guardianEmail, PatientColumn.signedName, PatientColumn.signedOn,
    PatientColumn.chartNote, PatientColumn.openingBalance, PatientColumn.balance, PatientColumn.completedVisits,
    PatientColumn.lastVisit, PatientColumn.registeredOn,
  ];

  static readonly person: ReadonlySet<PatientColumn> = new Set([
    PatientColumn.fullName, PatientColumn.phone, PatientColumn.email, PatientColumn.dateOfBirth, PatientColumn.sex,
    PatientColumn.address, PatientColumn.occupation, PatientColumn.emergencyName, PatientColumn.emergencyPhone,
  ]);

  static readonly intake: ReadonlySet<PatientColumn> = new Set([
    PatientColumn.reasonForVisit, PatientColumn.lastDentalVisit, PatientColumn.physicianName, PatientColumn.underTreatment,
    PatientColumn.treatmentDetails, PatientColumn.takesMedications, PatientColumn.medications, PatientColumn.allergies,
    PatientColumn.allergiesOther, PatientColumn.conditions, PatientColumn.conditionsOther, PatientColumn.pregnant,
    PatientColumn.nursing, PatientColumn.birthControl, PatientColumn.guardianName, PatientColumn.guardianRelationship,
    PatientColumn.guardianPhone, PatientColumn.guardianEmail, PatientColumn.signedName, PatientColumn.signedOn,
  ]);

  get isIntake(): boolean {
    return PatientColumn.intake.has(this);
  }

  /// What the column picker offers for a file's column.
  static get importable(): PatientColumn[] {
    return PatientColumn.values.filter((c) => !c.exportOnly);
  }

  /// An exported file's columns, in order. The front desk's has no notes
  /// column: they cannot read clinical notes, so it would only ever be blank,
  /// and blank looks like "none on file".
  static exported(withNotes: boolean): PatientColumn[] {
    return PatientColumn.values.filter((c) => !c.importOnly && (withNotes || c !== PatientColumn.chartNote));
  }

  /// The template: every column an import takes, as one would type them.
  static get template(): PatientColumn[] {
    return PatientColumn.values.filter((c) => !c.importOnly && !c.exportOnly && c !== PatientColumn.patientId);
  }

  get hint(): string {
    switch (this.cell) {
      case 'date':
        return 'a date';
      case 'yesNo':
        return 'Yes or No';
      case 'sex':
        return 'Female or Male';
      case 'allergies':
      case 'conditions':
        return 'a list, separated by ;';
      case 'money':
        return 'an amount in pesos';
      case 'relationship':
        return 'Parent or Guardian';
      default:
        if (this === PatientColumn.patientId) return 'from an export; leave empty for new patients';
        if (this === PatientColumn.signedName) return 'the name the form was signed with';
        if (this === PatientColumn.chartNote) return 'doctors and admins only';
        return 'text';
    }
  }
}

/// Each of [headers]' columns with the PatientColumn it most likely holds,
/// or none.
export function matchHeaders(headers: readonly string[]): (PatientColumn | null)[] {
  return matchColumns(headers, PatientColumn.importable);
}

/// Reads one row of a file whose columns are [columns] (from matchHeaders,
/// or as the person picked them).
export function readPatientRow(
  cells: readonly string[],
  columns: readonly (PatientColumn | null)[],
  row: number,
  dateOrder: DateOrder = 'month_first',
  now: Date = new Date(),
): ImportRow {
  const errors: string[] = [];
  const warnings: string[] = [];
  const values = cellsByColumn(cells, columns, (c) => c.exportOnly);

  const read = (c: PatientColumn): unknown => {
    const raw = values.get(c);
    if (raw == null) return null;
    switch (c.cell) {
      case 'text':
        return raw;
      case 'date': {
        const d = parseImportDate(raw, dateOrder, now);
        if (d == null) errors.push(`${c.header} "${raw}" is not a date.`);
        else if (c === PatientColumn.dateOfBirth && d.getTime() > now.getTime()) errors.push(`Birthday ${raw} is in the future.`);
        return d == null ? null : isoDate(d);
      }
      case 'yesNo': {
        const b = parseYesNo(raw);
        if (b == null) errors.push(`${c.header} "${raw}" is not Yes or No.`);
        return b;
      }
      case 'sex': {
        const s = parseSex(raw);
        if (s == null) errors.push(`Sex "${raw}" is not Female or Male.`);
        return s;
      }
      case 'money': {
        const m = parsePesos(raw);
        if (m == null) errors.push(`${c.header} "${raw}" is not an amount.`);
        else if (m < 0) errors.push(`${c.header} cannot be negative.`);
        return m;
      }
      case 'relationship':
        return parseRelationship(raw);
      case 'allergies':
      case 'conditions':
        return raw; // split below, with the "other" columns
    }
  };

  const person: Record<string, any> = {};
  const intake: Record<string, any> = {};
  const readValues = new Map<PatientColumn, unknown>();
  for (const c of PatientColumn.values) {
    const v = read(c);
    readValues.set(c, v);
    if (v == null) continue;
    if (PatientColumn.person.has(c)) person[c.key] = v;
    if (c.isIntake) intake[c.key] = v;
  }

  // The name: whole, "SURNAME, Given", or in parts.
  let name: string =
    (person.full_name as string | undefined) ??
    [values.get(PatientColumn.firstName), values.get(PatientColumn.middleName), values.get(PatientColumn.lastName)]
      .filter((s): s is string => s != null)
      .join(' ');
  name = tidyName(name);
  if (name === '') errors.push('No name.');
  else person.full_name = name;

  // Lists: what the form lists by name, the rest as "other".
  const rawAllergies = values.get(PatientColumn.allergies);
  if (rawAllergies != null) {
    const [known, other] = splitList(rawAllergies, allergyWords);
    intake.allergies = known;
    const rest = [other, values.get(PatientColumn.allergiesOther)].filter((s): s is string => s != null).join('; ');
    if (rest !== '') intake.allergies_other = rest;
  }
  const rawConditions = values.get(PatientColumn.conditions);
  if (rawConditions != null) {
    const [known, other] = splitList(rawConditions, conditionWords);
    intake.conditions = known;
    const rest = [other, values.get(PatientColumn.conditionsOther)].filter((s): s is string => s != null).join('; ');
    if (rest !== '') intake.conditions_other = rest;
  }

  // A medicine named answers "takes medications"; a treatment named answers
  // "under treatment". The reverse is never guessed.
  if (intake.medications != null) intake.takes_medications ??= true;
  if (intake.treatment_details != null) intake.under_treatment ??= true;

  if (intake.guardian_name != null && (intake.guardian_relationship == null || intake.guardian_phone == null)) {
    errors.push('A guardian needs a relationship (Parent or Guardian) and a phone.');
  }

  const opening = readValues.get(PatientColumn.openingBalance);
  const id = values.get(PatientColumn.patientId);
  const json: Record<string, any> = {
    row,
    ...(id != null ? { patient_id: id } : {}),
    ...(values.get(PatientColumn.chartNumber) != null ? { chart_number: values.get(PatientColumn.chartNumber) } : {}),
    person,
    ...(Object.keys(intake).length > 0 ? { intake } : {}),
    ...(values.get(PatientColumn.chartNote) != null ? { chart_note: values.get(PatientColumn.chartNote) } : {}),
    ...(typeof opening === 'number' && opening > 0 ? { opening_balance: opening.toFixed(2) } : {}),
  };

  if (id != null && !/^[0-9a-fA-F-]{36}$/.test(id)) {
    errors.push(`Patient ID "${id}" is not one this app made. Clear it for a new patient.`);
  }
  if (person.phone == null && name !== '') warnings.push('No phone number.');

  return new ImportRow(row, json, name, [...new Set(errors)], warnings, cells);
}

/// One export_patients row as the cells of [columns].
export function exportPatientCells(p: Record<string, any>, columns: readonly PatientColumn[]): string[] {
  const intake = (p.intake as Record<string, any> | null) ?? {};
  return columns.map((c) => {
    const v = c.isIntake ? intake[c.key] : p[c.key];
    if (v == null) return '';
    switch (c.cell) {
      case 'yesNo':
        return v === true ? 'Yes' : 'No';
      case 'sex': {
        const s = sexFromWire(v);
        return s == null ? '' : sexLabel[s];
      }
      case 'relationship':
        return guardianRelationshipLabel[guardianRelationshipFromWire(v)];
      case 'allergies':
        return (v as string[]).map((w) => intakeAllergyLabel[w as IntakeAllergy] ?? w).join('; ');
      case 'conditions':
        return (v as string[]).map((w) => intakeConditionLabel[w as IntakeCondition] ?? w).join('; ');
      case 'money':
        return Number(v).toFixed(2);
      default:
        return String(v);
    }
  });
}

// ── Reading cells ──────────────────────────────────────────────────────────

export function parseSex(raw: string): Sex | null {
  switch (raw.trim().toLowerCase()) {
    case 'f':
    case 'female':
    case 'babae':
    case 'woman':
      return 'female';
    case 'm':
    case 'male':
    case 'lalaki':
    case 'man':
      return 'male';
    default:
      return null;
  }
}

export function parseRelationship(raw: string): GuardianRelationship {
  return ['parent', 'mother', 'father', 'mom', 'dad', 'nanay', 'tatay', 'ina', 'ama', 'mama', 'papa'].includes(raw.trim().toLowerCase())
    ? 'parent'
    : 'guardian';
}

function splitList<T>(raw: string, words: ReadonlyMap<string, T>): [T[], string | null] {
  const known: T[] = [];
  const other: string[] = [];
  for (const part of raw.split(/[;,/\n]/)) {
    const p = part.trim();
    if (p === '' || blankWords.has(p.toLowerCase())) continue;
    const n = normHeader(p);
    let hit: T | undefined;
    for (const [word, value] of words) {
      // Whole words: "tb" is tuberculosis, but not inside another word.
      if (` ${n} `.includes(` ${word} `)) {
        hit = value;
        break;
      }
    }
    if (hit === undefined) other.push(p);
    else if (!known.includes(hit)) known.push(hit);
  }
  return [known, other.length === 0 ? null : other.join('; ')];
}

/// Words that name each item on the form's lists, as typed in files.
const allergyWords = new Map<string, IntakeAllergy>([
  ...intakeAllergies.map((a) => [normHeader(intakeAllergyLabel[a]), a] as [string, IntakeAllergy]),
  ...intakeAllergies.map((a) => [normHeader(a), a] as [string, IntakeAllergy]),
  ['anesthesia', 'local_anesthetic'],
  ['anesthetic', 'local_anesthetic'],
  ['anaesthetic', 'local_anesthetic'],
  ['lidocaine', 'local_anesthetic'],
  ['penicilin', 'penicillin'],
  ['amoxicillin', 'penicillin'],
  ['antibiotic', 'other_antibiotics'],
  ['sulfa', 'sulfa'],
  ['aspirin', 'aspirin'],
  ['latex', 'latex'],
]);

const conditionWords = new Map<string, IntakeCondition>([
  ...intakeConditions.map((c) => [normHeader(intakeConditionLabel[c]), c] as [string, IntakeCondition]),
  ...intakeConditions.map((c) => [normHeader(c), c] as [string, IntakeCondition]),
  ['hypertension', 'high_blood_pressure'],
  ['hypertensive', 'high_blood_pressure'],
  ['high bp', 'high_blood_pressure'],
  ['hbp', 'high_blood_pressure'],
  ['hypotension', 'low_blood_pressure'],
  ['low bp', 'low_blood_pressure'],
  ['heart', 'heart_disease'],
  ['cardiac', 'heart_disease'],
  ['diabetes', 'diabetes'],
  ['diabetic', 'diabetes'],
  ['asthma', 'asthma'],
  ['bleeding', 'bleeding_disorder'],
  ['hemophilia', 'bleeding_disorder'],
  ['anemia', 'anemia'],
  ['anemic', 'anemia'],
  ['hepatitis', 'hepatitis'],
  ['liver', 'hepatitis'],
  ['kidney', 'kidney_disease'],
  ['thyroid', 'thyroid_problem'],
  ['goiter', 'thyroid_problem'],
  ['epilepsy', 'epilepsy'],
  ['seizure', 'epilepsy'],
  ['stroke', 'stroke'],
  ['cancer', 'cancer'],
  ['tuberculosis', 'tuberculosis'],
  ['tb', 'tuberculosis'],
  ['ptb', 'tuberculosis'],
]);
