import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { ScrollView, View } from 'react-native';
import { Appbar, Button, Text } from 'react-native-paper';

import { useClinicNav } from '../app/navigation';
import { isStaffRole, registersPatients } from '../models/app_role';
import type { Patient } from '../models/patient';
import { guardianRelationshipLabel, intakeSourceDescription, sexLabel } from '../models/patient_intake';
import { combineAsync } from '../queries/async_value';
import { invalidatePatientLists, useMyPatient } from '../queries/catalog';
import { useCurrentClinic, useRefreshAccess, useRouteClinicSlug } from '../queries/clinic';
import { usePatientById } from '../queries/clinical';
import { useIntake } from '../queries/misc';
import { useAppRole, useCurrentUserId, useKiosk, useKioskActions, usePlatform } from '../state/platform';
import { ClinicMark } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, ErrorView, Loading } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Avatar, Gap, ListTile, Notice, Wrap } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { PatientIntakeForm } from '../widgets/patient_intake_form';
import { useStaffPin } from './staff_pin';

// ── Starting a form from the staff apps ─────────────────────────────────────

/// Handing the tablet to a patient: the form for [patientId], or for a new
/// patient. Asks the staff member to set a PIN first if they have none.
export function useStartKiosk(): (patientId?: string | null) => Promise<void> {
  const slug = useRouteClinicSlug();
  const pin = useStaffPin();
  const overlay = useOverlay();
  const kiosk = useKioskActions();
  const nav = useClinicNav();
  return async (patientId) => {
    if (slug == null) return;
    if (!(await pin.ensure())) return;
    const ready = await overlay.confirm({
      title: 'Hand the tablet over?',
      message: 'The app will show only the form until you enter your staff PIN. The patient cannot leave it or see anything else.',
      confirmLabel: 'Start',
    });
    if (!ready) return;
    kiosk.start(slug, patientId ?? null);
    nav.goTo(`/${slug}/kiosk`);
  };
}

/// "Add patient": the front desk fills the form in, or hands the tablet
/// over. Answers the new chart when the front desk filled it in; the
/// hand-off answers nothing, since the app is on the tablet screen by then.
export function useAddPatient(): () => Promise<Patient | null> {
  const overlay = useOverlay();
  const startKiosk = useStartKiosk();
  const { repo } = usePlatform();
  const qc = useQueryClient();
  return async () => {
    const choice = await overlay.showSheet<'handOver' | 'myself'>((close) => <AddPatientSheet close={close} />);
    if (choice == null) return null;
    if (choice === 'handOver') {
      await startKiosk();
      return null;
    }
    const id = await overlay.showPage<string>((close) => <StaffIntakeScreen close={close} />);
    if (id == null) return null;
    invalidatePatientLists(qc);
    return repo.fetchPatient(id);
  };
}

function AddPatientSheet({ close }: { close: Close<'handOver' | 'myself'> }) {
  return (
    <View style={{ paddingHorizontal: 16, paddingBottom: 16 }}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        Add patient
      </Text>
      <Gap size={12} />
      <ChoiceTile
        icon="tablet-android"
        title="Hand the tablet to the patient"
        subtitle="They fill in their own details and health history. Your staff PIN takes the tablet back."
        onPress={() => close('handOver')}
      />
      <Gap size={8} />
      <ChoiceTile
        icon="edit-note"
        title="Fill in the form myself"
        subtitle="For a patient on the phone, or reading it out."
        onPress={() => close('myself')}
      />
    </View>
  );
}

function ChoiceTile({ icon, title, subtitle, onPress }: { icon: IconName; title: string; subtitle: string; onPress: () => void }) {
  return (
    <AppCard>
      <ListTile
        style={{ paddingVertical: 14 }}
        leading={<Avatar icon={icon} />}
        title={<Text style={{ fontWeight: '600' }}>{title}</Text>}
        subtitle={subtitle}
        trailing={<Icon name="chevron-right" />}
        onPress={onPress}
      />
    </AppCard>
  );
}

// ── The front desk typing it in ─────────────────────────────────────────────

/// The form, filled in by staff: a new patient (no [patient]), or the form
/// on an existing chart. Closes with the chart id once saved.
export function StaffIntakeScreen({ patient, close }: { patient?: Patient | null; close: Close<string> }) {
  const clinic = useCurrentClinic().value ?? null;
  const app = useAppRole();
  const { repo } = usePlatform();
  const qc = useQueryClient();
  const startKiosk = useStartKiosk();
  const existing = patient ?? null;
  const intake = useIntake(existing?.id ?? '');

  if (existing != null && !intake.hasValue) {
    return (
      <Page title="Patient information" scroll={false}>
        {intake.hasError ? (
          <ErrorView error={intake.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['intake'] })} />
        ) : (
          <Loading />
        )}
      </Page>
    );
  }

  return (
    <Page
      title={existing == null ? 'New patient' : existing.name}
      scroll={false}
      actions={
        registersPatients(app) ? (
          // Nothing typed here carries over: the tablet opens its own form,
          // and going there closes this screen.
          <Button
            icon="tablet-android"
            onPress={() => {
              close();
              void startKiosk(existing?.id);
            }}
          >
            Hand to patient
          </Button>
        ) : undefined
      }
    >
      <PatientIntakeForm
        audience="staff"
        clinicName={clinic?.name ?? 'the clinic'}
        isDental={clinic?.isDental ?? false}
        patient={existing}
        intake={intake.value ?? null}
        submitLabel="Save"
        onSubmit={async (form) => {
          let id: string;
          if (existing == null) {
            id = await repo.registerPatient({ clinicId: clinic!.id, form, source: 'staff' });
          } else {
            await repo.savePatientIntake({ patientId: existing.id, form, source: 'staff' });
            id = existing.id;
            void qc.invalidateQueries({ queryKey: ['intake'] });
            void qc.invalidateQueries({ queryKey: ['patient'] });
            invalidatePatientLists(qc);
          }
          close(id);
        }}
      />
    </Page>
  );
}

// ── The tablet, in the patient's hands ──────────────────────────────────────

/// `/:clinic/kiosk`: the form, and nothing else, until a staff PIN.
///
/// The router sends every other URL here while a hand-off is on, so neither
/// the back button, a typed URL nor a reload gets the patient into the app.
/// The clinic switcher is deliberately absent too.
export function KioskScreen() {
  const session = useKiosk();
  const clinic = useCurrentClinic().value ?? null;
  const kiosk = useKioskActions();
  const pin = useStaffPin();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const { colors } = useAppTheme();

  if (session == null) return <Loading />;

  const unlock = async () => {
    if (!(await pin.verify(true))) return;
    const id = session.patientId;
    kiosk.end();
    invalidatePatientLists(qc);
    if (id != null) {
      void qc.invalidateQueries({ queryKey: ['intake'] });
      void qc.invalidateQueries({ queryKey: ['patient'] });
    }
    nav.goTo(`/${session.slug}/patients${id == null ? '' : `/${id}`}`);
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.surface }}>
      <Appbar.Header statusBarHeight={0} style={{ backgroundColor: colors.surface }}>
        <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10, paddingLeft: 8 }}>
          <ClinicMark clinic={clinic} size={28} />
          <Text variant="titleLarge" numberOfLines={1} style={{ flexShrink: 1 }}>
            {clinic?.name ?? ''}
          </Text>
        </View>
        <Button icon="lock-outline" onPress={unlock} style={{ marginRight: 8 }}>
          Staff
        </Button>
      </Appbar.Header>
      {session.submitted ? <KioskThanks onUnlock={unlock} /> : <KioskForm patientId={session.patientId} />}
    </View>
  );
}

function KioskForm({ patientId: id }: { patientId: string | null }) {
  const clinic = useCurrentClinic().value ?? null;
  const { repo } = usePlatform();
  const kiosk = useKioskActions();
  const qc = useQueryClient();
  const patient = usePatientById(id ?? '');
  const intake = useIntake(id ?? '');

  if (id != null && (!patient.hasValue || !intake.hasValue)) {
    return (
      <AsyncView
        value={combineAsync([patient, intake])}
        onRetry={() => {
          void qc.invalidateQueries({ queryKey: ['patient'] });
          void qc.invalidateQueries({ queryKey: ['intake'] });
        }}
      >
        {() => null}
      </AsyncView>
    );
  }

  return (
    <PatientIntakeForm
      // A fresh form per hand-off: never the previous patient's answers.
      key={id ?? 'new'}
      audience="patient"
      clinicName={clinic?.name ?? 'the clinic'}
      isDental={clinic?.isDental ?? false}
      patient={id == null ? null : patient.value}
      intake={id == null ? null : intake.value}
      submitLabel="Send"
      onSubmit={async (form) => {
        const chartId = id ?? (await repo.registerPatient({ clinicId: clinic!.id, form, source: 'front_desk_tablet' }));
        if (id != null) await repo.savePatientIntake({ patientId: id, form, source: 'front_desk_tablet' });
        kiosk.submitted(chartId);
      }}
    />
  );
}

function KioskThanks({ onUnlock }: { onUnlock: () => void }) {
  const { colors } = useAppTheme();
  return (
    <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 32 }}>
      <View style={{ width: '100%', maxWidth: 480, alignSelf: 'center', alignItems: 'center' }}>
        <Avatar icon="check" size={96} />
        <Text variant="headlineMedium" style={{ marginTop: 24, fontWeight: '700' }}>
          Thank you!
        </Text>
        <Text variant="titleMedium" style={{ marginTop: 12, textAlign: 'center', color: colors.onSurfaceVariant, lineHeight: 24 }}>
          Your information has been sent. Please hand the tablet back to the front desk.
        </Text>
        <Gap size={40} />
        <Button mode="outlined" icon="lock-open" onPress={onUnlock}>
          Front desk: unlock
        </Button>
      </View>
    </ScrollView>
  );
}

// ── The patient app ─────────────────────────────────────────────────────────

/// `/:clinic/intake` in the patient app: the form for the signed-in
/// patient's chart at this clinic.
///
/// Until it has been filled in once, the router sends every page at this
/// clinic here — right after sign-up and joining, before the home screen.
/// After that it is where the profile's "My information" leads.
export function MyIntakeScreen() {
  const clinic = useCurrentClinic().value ?? null;
  const me = useMyPatient();
  const { repo } = usePlatform();
  const qc = useQueryClient();
  const uid = useCurrentUserId();
  const refresh = useRefreshAccess();
  const nav = useClinicNav();
  const patient = me.value ?? null;
  const intake = useIntake(patient?.id ?? '');

  if (!me.hasValue) {
    return (
      <Page title="My information" scroll={false}>
        {me.hasError ? <ErrorView error={me.error} onRetry={() => void refresh()} /> : <Loading />}
      </Page>
    );
  }
  if (patient == null) {
    return (
      <Page title="My information" scroll={false}>
        <Text style={{ textAlign: 'center', marginTop: 48 }}>No chart at this clinic.</Text>
      </Page>
    );
  }
  const firstTime = patient.hasIntake === false;
  if (!intake.hasValue) {
    return (
      <Page title="My information" scroll={false}>
        {intake.hasError ? (
          <ErrorView error={intake.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['intake'] })} />
        ) : (
          <Loading />
        )}
      </Page>
    );
  }

  return (
    <Page
      title={firstTime ? `Welcome to ${clinic?.name ?? 'the clinic'}` : 'My information'}
      back={firstTime ? false : '/profile'}
      scroll={false}
      actions={firstTime ? <Button onPress={() => void repo.signOut()}>Sign out</Button> : undefined}
    >
      {firstTime && (
        <Notice icon="assignment-ind" tone="primary" style={{ borderRadius: 0 }}>
          Before your first visit, please tell the clinic a little about yourself. It takes about 3 minutes.
        </Notice>
      )}
      <PatientIntakeForm
        audience="patient"
        clinicName={clinic?.name ?? 'the clinic'}
        isDental={clinic?.isDental ?? false}
        patient={patient}
        intake={intake.value}
        submitLabel={firstTime ? 'Send' : 'Save'}
        onSubmit={async (form) => {
          await repo.savePatientIntake({ patientId: patient.id, form, source: 'patient_app' });
          void qc.invalidateQueries({ queryKey: ['intake'] });
          // The router's gate reads this; it must see the form as done
          // before the app moves on.
          await qc.invalidateQueries({ queryKey: ['myPatients'] });
          await qc.fetchQuery({ queryKey: ['myPatients', uid], queryFn: () => repo.fetchMyPatients() });
          if (!firstTime && nav.canGoBack()) nav.back();
          else nav.go('/home');
        }}
      />
    </Page>
  );
}

// ── On the patient's page (staff apps) ──────────────────────────────────────

/// The form on file, summarised for the staff apps: allergies first, then
/// medicines and conditions. Every staff member sees it — the front desk
/// included, by the clinic's choice. Staff can edit it; the front desk and
/// admins can also hand the tablet over to have the patient update it.
export function IntakeSection({ patient }: { patient: Patient }) {
  const app = useAppRole();
  const { colors } = useAppTheme();
  const overlay = useOverlay();
  const qc = useQueryClient();
  const startKiosk = useStartKiosk();
  const intakeAsync = useIntake(patient.id);
  if (!isStaffRole(app)) return null;

  const edit = async () => {
    const saved = await overlay.showPage<string>((close) => <StaffIntakeScreen patient={patient} close={close} />);
    if (saved != null) overlay.snack('Patient information saved');
  };

  const actions = (
    <Wrap>
      {registersPatients(app) && (
        <Button mode="contained-tonal" icon="tablet-android" onPress={() => void startKiosk(patient.id)}>
          Hand to patient
        </Button>
      )}
      <Button mode="outlined" icon="edit" onPress={edit}>
        {intakeAsync.value == null ? 'Fill in' : 'Edit'}
      </Button>
    </Wrap>
  );

  return (
    <AppCard padding={16} style={{ marginBottom: 12 }}>
      <AsyncView value={intakeAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['intake'] })}>
        {(intake) => {
          if (intake == null) {
            return (
              <View>
                <SectionTitle />
                <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
                  Not filled in yet. Ask about allergies and medicines before treatment.
                </Text>
                <Gap size={12} />
                {actions}
              </View>
            );
          }
          const female = patient.sex === 'female';
          const flags = [
            ...(female && intake.pregnant === true ? ['Pregnant'] : []),
            ...(female && intake.nursing === true ? ['Breastfeeding'] : []),
            ...(female && intake.birthControl === true ? ['On birth control pills'] : []),
          ];
          const g = intake.guardian;
          return (
            <View>
              <SectionTitle />
              <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>
                Filled in {intakeSourceDescription[intake.source]} · {format(intake.updatedAt, 'MMM d, y')}
              </Text>
              {g != null && (
                <View style={{ marginTop: 8 }}>
                  <Line
                    label="Filled in by"
                    value={[`${g.name} (${guardianRelationshipLabel[g.relationship]})`, g.phone, ...(g.email != null ? [g.email] : [])].join(' · ')}
                  />
                </View>
              )}
              <Gap size={12} />
              {intake.hasAllergies ? (
                <View style={{ flexDirection: 'row', gap: 8, padding: 12, marginBottom: 8, borderRadius: 12, backgroundColor: colors.errorContainer }}>
                  <Icon name="warning-amber" color={colors.onErrorContainer} />
                  <Text style={{ flex: 1, color: colors.onErrorContainer, fontWeight: '600' }}>
                    Allergic to {intake.allergyLabels.join(', ')}
                  </Text>
                </View>
              ) : (
                <Line label="Allergies" value="None reported" />
              )}
              <Line label="Medicines" value={intake.takesMedications ? intake.medications ?? 'Yes' : 'None'} />
              <Line label="Conditions" value={intake.conditionLabels.length === 0 ? 'None reported' : intake.conditionLabels.join(', ')} />
              {intake.underTreatment && <Line label="Under treatment" value={intake.treatmentDetails ?? 'Yes'} />}
              {flags.length > 0 && <Line label="Also" value={flags.join(' · ')} />}
              {intake.physicianName != null && <Line label="Physician" value={intake.physicianName} />}
              {intake.lastDentalVisit != null && <Line label="Last dental visit" value={intake.lastDentalVisit} />}
              {intake.reasonForVisit != null && <Line label="Reason for visit" value={intake.reasonForVisit} />}
              {(patient.emergencyContactName != null || patient.emergencyContactPhone != null) && (
                <Line
                  label="Emergency contact"
                  value={[patient.emergencyContactName, patient.emergencyContactPhone].filter((s): s is string => s != null).join(' · ')}
                />
              )}
              {patient.address != null && <Line label="Address" value={patient.address} />}
              {patient.sex != null && <Line label="Sex" value={sexLabel[patient.sex]} />}
              {patient.occupation != null && <Line label="Occupation" value={patient.occupation} />}
              <Gap size={12} />
              {actions}
            </View>
          );
        }}
      </AsyncView>
    </AppCard>
  );
}

function SectionTitle() {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
      <Icon name="assignment-ind" size={20} color={colors.primary} />
      <Text style={{ fontWeight: '700', fontSize: 16 }}>Patient information</Text>
    </View>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', paddingVertical: 3 }}>
      <Text style={{ width: 130, fontSize: 13, color: colors.onSurfaceVariant }}>{label}</Text>
      <Text style={{ flex: 1, fontSize: 14 }}>{value}</Text>
    </View>
  );
}

