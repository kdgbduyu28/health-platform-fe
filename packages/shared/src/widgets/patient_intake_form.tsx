import { format } from 'date-fns';
import { useRef, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Checkbox, Chip, HelperText, ProgressBar, Switch, Text, TextInput } from 'react-native-paper';

import type { Patient } from '../models/patient';
import {
  type GuardianRelationship,
  type IntakeAllergy,
  type IntakeCondition,
  type IntakeSubmission,
  type PatientIntake,
  type Sex,
  guardianRelationshipLabel,
  guardianRelationships,
  intakeAllergies,
  intakeAllergyLabel,
  intakeConditionLabel,
  intakeConditions,
  sexLabel,
  sexes,
} from '../models/patient_intake';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField, useDatePicker } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Gap } from '../ui/kit';
import { useOverlay } from '../ui/overlay';
import { formatDay } from '../util/dates';

/// Who is holding the device, which decides the wording: "your birthday" for
/// the patient, "the patient's birthday" for the front desk.
export type IntakeAudience = 'patient' | 'staff';

type Step = 'about' | 'contact' | 'health' | 'consent';
const steps: readonly Step[] = ['about', 'contact', 'health', 'consent'];
const stepMeta: Record<Step, { patientTitle: string; staffTitle: string; icon: IconName }> = {
  about: { patientTitle: 'About you', staffTitle: 'About the patient', icon: 'person-outline' },
  contact: { patientTitle: 'Contact', staffTitle: 'Contact', icon: 'phone' },
  health: { patientTitle: 'Health', staffTitle: 'Health', icon: 'favorite-outline' },
  consent: { patientTitle: 'Review & consent', staffTitle: 'Review & consent', icon: 'verified' },
};

/// A real calendar date from MM/DD/YYYY, or null. `new Date` rolls 02/31
/// over into March, so the parts are checked against what comes back.
export function parseDobText(text: string): Date | null {
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(text.trim());
  if (!m) return null;
  const month = Number(m[1]);
  const day = Number(m[2]);
  const year = Number(m[3]);
  const d = new Date(year, month - 1, day);
  return d.getFullYear() === year && d.getMonth() === month - 1 && d.getDate() === day ? d : null;
}

/// Digits only, with the slashes put in as they are typed: MM/DD/YYYY.
export function maskDob(text: string): string {
  const digits = text.replace(/\D/g, '').slice(0, 8);
  let out = '';
  for (let i = 0; i < digits.length; i++) {
    if (i === 2 || i === 4) out += '/';
    out += digits[i];
  }
  return out;
}

const validEmail = (v: string) => (v.trim() === '' || v.includes('@') ? null : 'Check the email address');
const validPhone = (v: string) => (v.replace(/\D/g, '').length < 7 ? 'Check the number' : null);

type Texts = {
  name: string;
  dob: string;
  occupation: string;
  phone: string;
  email: string;
  address: string;
  ecName: string;
  ecPhone: string;
  reason: string;
  lastDental: string;
  physician: string;
  treatment: string;
  medications: string;
  allergiesOther: string;
  conditionsOther: string;
  signedName: string;
  gName: string;
  gPhone: string;
  gEmail: string;
};

type ErrorKey = keyof Texts | 'gRelationship' | 'sex' | 'underTreatment' | 'takesMedications' | 'consent';

/// The patient information form, four steps: about you, contact, health, and
/// consent. The same form everywhere — the front desk typing it in, the
/// patient on the front desk tablet, the patient in the patient app — so a
/// clinic gets the same answers however they arrive.
///
/// Built for a tablet held by someone who has never seen the app: one topic
/// per step, big targets, and nothing but Back and Next to find. Fills the
/// space it is given; the caller supplies the page around it.
///
/// [patient] and [intake] prefill it (an existing chart, or a signed-up
/// patient's name and email). Consent is never prefilled: whoever saves the
/// form agrees again.
///
/// Optionally a parent or guardian answers for the patient (a child, or an
/// adult who cannot answer for themself): they give their own details first,
/// the questions then ask about "the patient", and they sign.
export function PatientIntakeForm({
  audience,
  clinicName,
  isDental,
  onSubmit,
  patient,
  intake,
  submitLabel = 'Submit',
}: {
  audience: IntakeAudience;
  clinicName: string;
  /// Adds the dental questions (last dental visit).
  isDental: boolean;
  /// Saves the form. Throw to keep the form open with the error shown.
  onSubmit: (form: IntakeSubmission) => Promise<void>;
  patient?: Patient | null;
  intake?: PatientIntake | null;
  submitLabel?: string;
}) {
  const { colors } = useAppTheme();
  const overlay = useOverlay();
  const pickDate = useDatePicker();
  const scroll = useRef<ScrollView>(null);
  const [step, setStep] = useState<Step>('about');

  const [t, setT] = useState<Texts>(() => ({
    name: patient?.name ?? '',
    dob: patient?.dateOfBirth == null ? '' : format(patient.dateOfBirth, 'MM/dd/yyyy'),
    occupation: patient?.occupation ?? '',
    phone: patient?.phone ?? '',
    email: patient?.email ?? '',
    address: patient?.address ?? '',
    ecName: patient?.emergencyContactName ?? '',
    ecPhone: patient?.emergencyContactPhone ?? '',
    reason: intake?.reasonForVisit ?? '',
    lastDental: intake?.lastDentalVisit ?? '',
    physician: intake?.physicianName ?? '',
    treatment: intake?.treatmentDetails ?? '',
    medications: intake?.medications ?? '',
    allergiesOther: intake?.allergiesOther ?? '',
    conditionsOther: intake?.conditionsOther ?? '',
    signedName: '',
    gName: intake?.guardian?.name ?? '',
    gPhone: intake?.guardian?.phone ?? '',
    gEmail: intake?.guardian?.email ?? '',
  }));
  const [byGuardian, setByGuardian] = useState(intake?.guardian != null);
  const [gRelationship, setGRelationship] = useState<GuardianRelationship | null>(intake?.guardian?.relationship ?? null);
  const [sex, setSex] = useState<Sex | null>(patient?.sex ?? null);
  const [underTreatment, setUnderTreatment] = useState<boolean | null>(intake?.underTreatment ?? null);
  const [takesMedications, setTakesMedications] = useState<boolean | null>(intake?.takesMedications ?? null);
  const [allergies, setAllergies] = useState<Set<IntakeAllergy>>(() => new Set(intake?.allergies ?? []));
  const [conditions, setConditions] = useState<Set<IntakeCondition>>(() => new Set(intake?.conditions ?? []));
  const [pregnant, setPregnant] = useState<boolean | null>(intake?.pregnant ?? null);
  const [nursing, setNursing] = useState<boolean | null>(intake?.nursing ?? null);
  const [birthControl, setBirthControl] = useState<boolean | null>(intake?.birthControl ?? null);
  const [consent, setConsent] = useState(false);
  const [errors, setErrors] = useState<Partial<Record<ErrorKey, string | null>>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /// The device is with the patient's side (the patient or their guardian),
  /// not the front desk. Decides the wording of the dialogs and the consent.
  const holding = audience === 'patient';
  /// The patient is holding the device, answering about themself.
  const you = holding && !byGuardian;
  /// "your" / "the patient's" and friends, by who the questions are about.
  const w = (forPatient: string, forStaff: string) => (you ? forPatient : forStaff);

  const set = (key: keyof Texts) => (value: string) => {
    setT((prev) => ({ ...prev, [key]: value }));
    if (errors[key]) setErrors((e) => ({ ...e, [key]: null }));
  };
  const clear = (key: ErrorKey) => errors[key] && setErrors((e) => ({ ...e, [key]: null }));

  const go = (next: Step) => {
    setStep(next);
    setError(null);
    scroll.current?.scrollTo({ y: 0, animated: false });
  };

  const validateStep = (): boolean => {
    const e: Partial<Record<ErrorKey, string | null>> = {};
    const required = (key: keyof Texts, extra?: (v: string) => string | null) => {
      const v = t[key];
      e[key] = v.trim() === '' ? 'Required' : extra?.(v) ?? null;
    };
    if (step === 'about') {
      if (byGuardian) {
        required('gName');
        e.gRelationship = gRelationship == null ? 'Please choose one' : null;
        required('gPhone', validPhone);
        e.gEmail = validEmail(t.gEmail);
      }
      required('name');
      const now = new Date();
      if (t.dob.trim() === '') e.dob = 'Required';
      else {
        const d = parseDobText(t.dob);
        if (d == null) e.dob = 'Use MM/DD/YYYY, e.g. 04/02/1990';
        else if (d.getTime() > now.getTime() || d.getFullYear() < now.getFullYear() - 120) e.dob = 'Check the year';
      }
      e.sex = sex == null ? 'Please choose one' : null;
    } else if (step === 'contact') {
      required('phone', validPhone);
      e.email = validEmail(t.email);
      e.ecPhone = t.ecPhone.trim() === '' ? null : validPhone(t.ecPhone);
    } else if (step === 'health') {
      e.underTreatment = underTreatment == null ? 'Please answer' : null;
      e.takesMedications = takesMedications == null ? 'Please answer' : null;
      if (takesMedications === true) required('medications');
    } else {
      e.consent = consent
        ? null
        : holding
          ? 'Please tick the box to continue'
          : byGuardian
            ? 'The parent or guardian must agree before saving'
            : 'The patient must agree before saving';
      required('signedName');
    }
    setErrors(e);
    return Object.values(e).every((v) => !v);
  };

  const submission = (): IntakeSubmission => {
    const text = (v: string) => (v.trim() === '' ? null : v.trim());
    const dob = parseDobText(t.dob);
    const female = sex === 'female';
    return {
      person: {
        full_name: t.name.trim(),
        date_of_birth: dob == null ? null : formatDay(dob),
        sex: sex,
        occupation: text(t.occupation),
        phone: text(t.phone),
        email: text(t.email),
        address: text(t.address),
        emergency_contact_name: text(t.ecName),
        emergency_contact_phone: text(t.ecPhone),
      },
      intake: {
        reason_for_visit: text(t.reason),
        last_dental_visit: isDental ? text(t.lastDental) : null,
        physician_name: text(t.physician),
        under_treatment: underTreatment,
        treatment_details: text(t.treatment),
        takes_medications: takesMedications,
        medications: text(t.medications),
        allergies: [...allergies],
        allergies_other: text(t.allergiesOther),
        conditions: [...conditions],
        conditions_other: text(t.conditionsOther),
        pregnant: female ? pregnant : null,
        nursing: female ? nursing : null,
        birth_control: female ? birthControl : null,
        filled_by_guardian: byGuardian,
        ...(byGuardian
          ? {
              guardian_name: t.gName.trim(),
              guardian_relationship: gRelationship,
              guardian_phone: t.gPhone.trim(),
              guardian_email: text(t.gEmail),
            }
          : {}),
        signed_name: t.signedName.trim(),
        consent,
      },
    };
  };

  const submit = async () => {
    if (busy) return;
    const confirmed = await overlay.confirm({
      title: holding ? (byGuardian ? 'Send this information?' : 'Send your information?') : 'Save this form?',
      message: holding
        ? 'Please check that everything is correct. You can go back and change anything before sending.'
        : byGuardian
          ? 'Check the answers with the parent or guardian before saving.'
          : 'Check the answers with the patient before saving.',
      cancelLabel: 'Check again',
      confirmLabel: submitLabel,
    });
    if (!confirmed) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(submission());
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const next = () => {
    if (!validateStep()) return;
    if (step === 'consent') void submit();
    else go(steps[steps.indexOf(step) + 1]);
  };

  const field = (
    key: keyof Texts,
    label: string,
    opts: {
      hint?: string;
      helper?: string;
      required?: boolean;
      keyboard?: 'phone-pad' | 'email-address' | 'number-pad';
      capitalize?: 'words' | 'sentences';
      lines?: number;
      autoComplete?: 'name' | 'tel' | 'email';
    } = {},
  ) => (
    <TextField
      key={key}
      style={{ marginBottom: 16 }}
      label={opts.required ? `${label} *` : label}
      placeholder={opts.hint}
      helperText={opts.helper}
      value={t[key]}
      onChangeText={set(key)}
      error={errors[key]}
      keyboardType={opts.keyboard}
      autoCapitalize={opts.capitalize ?? 'none'}
      multiline={(opts.lines ?? 1) > 1}
      minLines={opts.lines}
      autoComplete={opts.autoComplete}
    />
  );

  const index = steps.indexOf(step);
  const last = step === 'consent';
  const title =
    step === 'about' && byGuardian
      ? holding
        ? 'About you and the patient'
        : 'Guardian and patient'
      : you
        ? stepMeta[step].patientTitle
        : stepMeta[step].staffTitle;

  const aboutStep = (
    <>
      {/* Optional: off unless a parent or guardian is answering. */}
      <AppCard color={byGuardian ? colors.secondaryContainer : undefined} style={{ marginBottom: 20 }}>
        <Pressable onPress={() => setByGuardian((v) => !v)} style={{ flexDirection: 'row', alignItems: 'center', padding: 16, gap: 16 }}>
          <Icon name="family-restroom" color={colors.onSurfaceVariant} />
          <View style={{ flex: 1 }}>
            <Text variant="bodyLarge">
              {holding ? "I'm a parent or guardian filling this in for the patient" : 'A parent or guardian is answering for the patient'}
            </Text>
            <Text style={{ color: colors.onSurfaceVariant }}>For a child, or someone who cannot answer for themself</Text>
          </View>
          <Switch value={byGuardian} onValueChange={setByGuardian} />
        </Pressable>
      </AppCard>
      {byGuardian && (
        <>
          <SectionLabel text={holding ? 'About you (parent or guardian)' : 'Parent or guardian'} />
          {field('gName', holding ? 'Your full name' : 'Their full name', {
            required: true,
            capitalize: 'words',
            autoComplete: holding ? 'name' : undefined,
          })}
          <Question label={holding ? "You are the patient's" : "They are the patient's"}>
            <ChoiceField
              value={gRelationship}
              options={guardianRelationships.map((r) => [r, guardianRelationshipLabel[r]] as const)}
              onChange={(v) => {
                setGRelationship(v);
                clear('gRelationship');
              }}
              error={errors.gRelationship}
            />
          </Question>
          {field('gPhone', holding ? 'Your mobile number' : 'Their mobile number', {
            required: true,
            keyboard: 'phone-pad',
            autoComplete: holding ? 'tel' : undefined,
          })}
          {field('gEmail', holding ? 'Your email' : 'Their email', {
            keyboard: 'email-address',
            autoComplete: holding ? 'email' : undefined,
          })}
          <Gap size={8} />
          <SectionLabel text="About the patient" />
        </>
      )}
      {field('name', byGuardian ? "Patient's full name" : 'Full name', {
        required: true,
        capitalize: 'words',
        autoComplete: you ? 'name' : undefined,
      })}
      {/* MM/DD/YYYY, as Filipino forms write it. Typed rather than picked: a
          calendar is a long way to scroll to 1958. The calendar is there too. */}
      <View style={{ marginBottom: 16 }}>
        <TextInput
          mode="outlined"
          label={`${w('Your birthday', 'Birthday')} *`}
          placeholder="MM/DD/YYYY"
          value={t.dob}
          onChangeText={(v) => set('dob')(maskDob(v))}
          keyboardType="number-pad"
          error={!!errors.dob}
          outlineColor="transparent"
          outlineStyle={{ borderRadius: 12 }}
          style={{ backgroundColor: colors.surfaceContainerHighest }}
          right={
            <TextInput.Icon
              icon="calendar-month"
              accessibilityLabel="Pick from a calendar"
              onPress={async () => {
                const now = new Date();
                const picked = await pickDate({
                  initial: parseDobText(t.dob) ?? new Date(now.getFullYear() - 30, 0, 1),
                  first: new Date(now.getFullYear() - 120, 0, 1),
                  last: now,
                  title: w('Your birthday', 'Birthday'),
                });
                if (picked) set('dob')(format(picked, 'MM/dd/yyyy'));
              }}
            />
          }
        />
        {errors.dob ? (
          <HelperText type="error" visible>
            {errors.dob}
          </HelperText>
        ) : null}
      </View>
      <Question label="Sex">
        <ChoiceField
          value={sex}
          options={sexes.map((s) => [s, sexLabel[s]] as const)}
          onChange={(v) => {
            setSex(v);
            clear('sex');
          }}
          error={errors.sex}
        />
      </Question>
      {field('occupation', 'Occupation', { capitalize: 'sentences' })}
    </>
  );

  const contactStep = (
    <>
      {field('phone', 'Mobile number', {
        helper: byGuardian
          ? `The patient's own. If they have none, use ${holding ? 'yours' : "the parent or guardian's"}.`
          : undefined,
        required: true,
        keyboard: 'phone-pad',
        autoComplete: 'tel',
      })}
      {field('email', 'Email', { keyboard: 'email-address', autoComplete: 'email' })}
      {field('address', 'Home address', { capitalize: 'words', lines: 2 })}
      <Gap size={8} />
      <SectionLabel text={w('Who should we call in an emergency?', 'Emergency contact')} />
      {field('ecName', 'Contact name', { capitalize: 'words' })}
      {field('ecPhone', 'Contact number', { keyboard: 'phone-pad' })}
    </>
  );

  const yesNo = [
    [true, 'Yes'],
    [false, 'No'],
  ] as const;

  const healthStep = (
    <>
      {field('reason', w('What brings you in today?', 'Reason for visit'), { capitalize: 'sentences', lines: 2 })}
      {isDental && field('lastDental', 'Last dental visit', { hint: 'e.g. about a year ago', capitalize: 'sentences' })}
      {field('physician', w('Your regular doctor (if any)', 'Physician (if any)'), { capitalize: 'words' })}
      <Question label={w('Are you being treated by a doctor right now?', "Under a doctor's treatment now?")}>
        <ChoiceField
          value={underTreatment}
          options={yesNo}
          onChange={(v) => {
            setUnderTreatment(v);
            clear('underTreatment');
          }}
          error={errors.underTreatment}
        />
      </Question>
      {underTreatment === true && field('treatment', 'For what?', { capitalize: 'sentences' })}
      <Question label={w('Are you taking any medicines?', 'Taking any medicines?')}>
        <ChoiceField
          value={takesMedications}
          options={yesNo}
          onChange={(v) => {
            setTakesMedications(v);
            clear('takesMedications');
          }}
          error={errors.takesMedications}
        />
      </Question>
      {takesMedications === true &&
        field('medications', 'Which ones?', {
          hint: 'Name and dose, e.g. Losartan 50 mg',
          required: true,
          capitalize: 'sentences',
          lines: 2,
        })}
      <Gap size={8} />
      <SectionLabel text={w('Are you allergic to any of these?', 'Allergies')} />
      <Text style={{ color: colors.onSurfaceVariant }}>Tap all that apply. Leave blank if none.</Text>
      <Gap size={8} />
      <Chips
        options={intakeAllergies.map((a) => [a, intakeAllergyLabel[a]] as const)}
        selected={allergies}
        onChange={setAllergies}
        selectedColor={colors.errorContainer}
      />
      {field('allergiesOther', 'Other allergies', { capitalize: 'sentences' })}
      <Gap size={8} />
      <SectionLabel text={w('Do you have, or have you had, any of these?', 'Medical conditions')} />
      <Text style={{ color: colors.onSurfaceVariant }}>Tap all that apply. Leave blank if none.</Text>
      <Gap size={8} />
      <Chips options={intakeConditions.map((c) => [c, intakeConditionLabel[c]] as const)} selected={conditions} onChange={setConditions} />
      {field('conditionsOther', 'Other conditions', { capitalize: 'sentences' })}
      {sex === 'female' && (
        <>
          <Gap size={8} />
          <SectionLabel text={w('For women', 'Women')} />
          <Question label={w('Are you pregnant?', 'Pregnant?')}>
            <ChoiceField value={pregnant} options={yesNo} onChange={setPregnant} />
          </Question>
          <Question label={w('Are you breastfeeding?', 'Breastfeeding?')}>
            <ChoiceField value={nursing} options={yesNo} onChange={setNursing} />
          </Question>
          <Question label={w('Are you taking birth control pills?', 'On birth control pills?')}>
            <ChoiceField value={birthControl} options={yesNo} onChange={setBirthControl} />
          </Question>
        </>
      )}
    </>
  );

  const consentStep = () => {
    const dob = parseDobText(t.dob);
    const allergyList = [
      ...intakeAllergies.filter((a) => allergies.has(a)).map((a) => intakeAllergyLabel[a]),
      ...(t.allergiesOther.trim() !== '' ? [t.allergiesOther.trim()] : []),
    ];
    const conditionList = [
      ...intakeConditions.filter((c) => conditions.has(c)).map((c) => intakeConditionLabel[c]),
      ...(t.conditionsOther.trim() !== '' ? [t.conditionsOther.trim()] : []),
    ];
    return (
      <>
        <AppCard padding={16}>
          {byGuardian && (
            <ReviewRow
              label="Filled in by"
              value={[
                t.gName.trim(),
                ...(gRelationship != null ? [`(${guardianRelationshipLabel[gRelationship]})`] : []),
                ...(t.gPhone.trim() !== '' ? [`· ${t.gPhone.trim()}`] : []),
              ].join(' ')}
              onEdit={() => go('about')}
            />
          )}
          <ReviewRow label="Name" value={t.name.trim()} onEdit={() => go('about')} />
          <ReviewRow label="Birthday" value={dob == null ? '—' : format(dob, 'MMMM d, y')} onEdit={() => go('about')} />
          <ReviewRow label="Mobile" value={t.phone.trim()} onEdit={() => go('contact')} />
          <ReviewRow
            label="Emergency contact"
            value={[t.ecName.trim(), t.ecPhone.trim()].filter((s) => s !== '').join(' · ')}
            onEdit={() => go('contact')}
          />
          <ReviewRow label="Medicines" value={takesMedications === true ? t.medications.trim() : 'None'} onEdit={() => go('health')} />
          <ReviewRow
            label="Allergies"
            value={allergyList.length === 0 ? 'None' : allergyList.join(', ')}
            highlight={allergyList.length > 0}
            onEdit={() => go('health')}
          />
          <ReviewRow label="Conditions" value={conditionList.length === 0 ? 'None' : conditionList.join(', ')} onEdit={() => go('health')} />
        </AppCard>
        <Gap size={24} />
        <Pressable
          onPress={() => {
            setConsent((c) => !c);
            clear('consent');
          }}
          style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 8 }}
        >
          <Checkbox.Android status={consent ? 'checked' : 'unchecked'} onPress={() => {
            setConsent((c) => !c);
            clear('consent');
          }} />
          <Text variant="bodyLarge" style={{ flex: 1, paddingTop: 6 }}>
            {consentText(clinicName, holding, byGuardian)}
          </Text>
        </Pressable>
        {errors.consent ? (
          <HelperText type="error" visible>
            {errors.consent}
          </HelperText>
        ) : null}
        <Gap size={12} />
        {field(
          'signedName',
          holding
            ? 'Type your full name to sign'
            : byGuardian
              ? "Parent or guardian's full name (signature)"
              : "Patient's full name (signature)",
          { required: true, capitalize: 'words' },
        )}
      </>
    );
  };

  return (
    <View style={{ flex: 1 }}>
      <ProgressBar progress={(index + 1) / steps.length} style={{ height: 4 }} />
      <ScrollView ref={scroll} style={{ flex: 1 }} contentContainerStyle={{ padding: 24, paddingBottom: 32 }} keyboardShouldPersistTaps="handled">
        <View style={{ width: '100%', maxWidth: 640, alignSelf: 'center' }}>
          <Text variant="labelLarge" style={{ color: colors.primary }}>
            Step {index + 1} of {steps.length}
          </Text>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 4 }}>
            <Icon name={stepMeta[step].icon} color={colors.primary} />
            <Text variant="headlineSmall" style={{ flex: 1, fontWeight: '700' }}>
              {title}
            </Text>
          </View>
          <Gap size={24} />
          {step === 'about' ? aboutStep : step === 'contact' ? contactStep : step === 'health' ? healthStep : consentStep()}
        </View>
      </ScrollView>
      <View style={{ backgroundColor: colors.surfaceContainer, paddingHorizontal: 24, paddingVertical: 12, boxShadow: '0 -1px 4px rgba(0,0,0,0.12)' } as never}>
        <View style={{ width: '100%', maxWidth: 640, alignSelf: 'center' }}>
          {error != null && <Text style={{ marginBottom: 8, textAlign: 'center', color: colors.error }}>{error}</Text>}
          <View style={{ flexDirection: 'row', gap: 12 }}>
            {step !== 'about' && (
              <Button mode="outlined" icon="arrow-back" style={{ flex: 1 }} contentStyle={{ height: 56 }} disabled={busy} onPress={() => go(steps[index - 1])}>
                Back
              </Button>
            )}
            <Button
              mode="contained"
              icon={busy ? undefined : last ? 'check' : 'arrow-forward'}
              style={{ flex: 2 }}
              contentStyle={{ height: 56, flexDirection: last ? 'row' : 'row-reverse' }}
              labelStyle={{ fontSize: 17, fontWeight: '600' }}
              disabled={busy}
              onPress={next}
            >
              {busy ? <ActivityIndicator size={20} /> : last ? submitLabel : 'Next'}
            </Button>
          </View>
        </View>
      </View>
    </View>
  );
}

export function consentText(clinic: string, holding: boolean, byGuardian: boolean): string {
  const law = 'as allowed by the Data Privacy Act of 2012 (RA 10173).';
  if (!byGuardian) {
    return holding
      ? `I confirm that this information is true and complete, and I agree to ${clinic} collecting and using it to care for me, ${law}`
      : `The patient confirms that this information is true and complete, and agrees to ${clinic} collecting and using it for their care, ${law}`;
  }
  return holding
    ? `As the patient's parent or guardian, I confirm that this information is true and complete, and I agree on their behalf to ${clinic} collecting and using it for their care, ${law}`
    : `The patient's parent or guardian confirms that this information is true and complete, and agrees on the patient's behalf to ${clinic} collecting and using it for their care, ${law}`;
}

function SectionLabel({ text }: { text: string }) {
  return (
    <Text variant="titleMedium" style={{ fontWeight: '600', marginBottom: 8 }}>
      {text}
    </Text>
  );
}

function Question({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ marginBottom: 20 }}>
      <Text style={{ fontSize: 16 }}>{label}</Text>
      <Gap size={8} />
      {children}
    </View>
  );
}

/// One answer from a few, as big side-by-side buttons.
function ChoiceField<T extends string | boolean>({
  value,
  options,
  onChange,
  error,
}: {
  value: T | null;
  options: readonly (readonly [T, string])[];
  onChange: (value: T) => void;
  error?: string | null;
}) {
  return (
    <View>
      <View style={{ flexDirection: 'row', gap: 12 }}>
        {options.map(([v, label]) => (
          <Button
            key={String(v)}
            mode={value === v ? 'contained' : 'outlined'}
            icon={value === v ? 'check' : undefined}
            style={{ flex: 1 }}
            contentStyle={{ height: 52 }}
            onPress={() => onChange(v)}
          >
            {label}
          </Button>
        ))}
      </View>
      {error ? (
        <HelperText type="error" visible>
          {error}
        </HelperText>
      ) : null}
    </View>
  );
}

function Chips<T extends string>({
  options,
  selected,
  onChange,
  selectedColor,
}: {
  options: readonly (readonly [T, string])[];
  selected: Set<T>;
  onChange: (next: Set<T>) => void;
  selectedColor?: string;
}) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 12 }}>
      {options.map(([v, label]) => {
        const on = selected.has(v);
        return (
          <Chip
            key={v}
            mode="outlined"
            selected={on}
            showSelectedCheck
            style={on && selectedColor ? { backgroundColor: selectedColor } : undefined}
            textStyle={{ fontSize: 15 }}
            onPress={() => {
              const next = new Set(selected);
              if (on) next.delete(v);
              else next.add(v);
              onChange(next);
            }}
          >
            {label}
          </Chip>
        );
      })}
    </View>
  );
}

function ReviewRow({ label, value, onEdit, highlight = false }: { label: string; value: string; onEdit: () => void; highlight?: boolean }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onEdit} style={{ flexDirection: 'row', alignItems: 'flex-start', paddingVertical: 8, paddingHorizontal: 4, borderRadius: 8 }}>
      <Text style={{ width: 140, color: colors.onSurfaceVariant }}>{label}</Text>
      <Text style={{ flex: 1, fontWeight: '600', color: highlight ? colors.error : undefined }}>{value === '' ? '—' : value}</Text>
      <Icon name="edit" size={18} color={colors.outline} />
    </Pressable>
  );
}
