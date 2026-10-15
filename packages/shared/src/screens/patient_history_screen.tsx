import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { Button, FAB, Text } from 'react-native-paper';

import { CardColumns, ContentWidth, SplitColumns } from '../app/adaptive';
import type { Appointment } from '../models/appointment';
import { holdsTime, isOpenStatus } from '../models/appointment_status';
import type { DentalEntry, DentalEntryStatus } from '../models/dental_chart';
import { formatPeso } from '../models/money';
import type { Patient } from '../models/patient';
import type { PatientIntake } from '../models/patient_intake';
import { sexLabel } from '../models/patient_intake';
import { usePatientInvoices } from '../queries/billing';
import { useCurrentClinic } from '../queries/clinic';
import { useCanSeeClinicalNotes, usePatientById, usePatientHistory } from '../queries/clinical';
import { useCanSeeAuditLog, useClinicChartsTeeth, useDentalChart, useIntake } from '../queries/misc';
import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { AsyncView, ErrorView, Loading } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, Avatar, ListTile, Tabs } from '../ui/kit';
import { BarAction, Page } from '../ui/page';
import { daysBetween } from '../util/dates';
import { StatusBadge } from '../widgets/appointment_bits';
import { AuditLogView } from '../widgets/audit_log_view';
import { InvoiceTile } from '../widgets/billing_widgets';
import { ChartNoteSection } from '../widgets/clinical_notes';
import { DentalChartSection, DentalEntryTile, VisitDentalLine, useToothNumbering } from '../widgets/dental_chart';
import { patientRemarks } from '../models/patient_remarks';
import { RemarkChips, remarkColor } from '../widgets/patient_remarks';
import { usePrintStatement } from '../widgets/print_statement_sheet';
import { useRecordVisitSheet } from '../widgets/record_visit_sheet';
import { IntakeSection } from './intake_screens';

const date = (d: Date) => format(d, 'MMM d, y');

/// "3 months ago", "in 2 weeks", "today".
export function relativeDay(d: Date, now: Date = new Date()): string {
  const days = daysBetween(now, d);
  if (days === 0) return 'today';
  if (days === -1) return 'yesterday';
  if (days === 1) return 'tomorrow';
  const n = Math.abs(days);
  const [count, unit] =
    n < 14 ? [n, 'day'] : n < 60 ? [Math.floor(n / 7), 'week'] : n < 730 ? [Math.floor(n / 30), 'month'] : [Math.floor(n / 365), 'year'];
  const text = `${count} ${unit}${count === 1 ? '' : 's'}`;
  return days < 0 ? `${text} ago` : `in ${text}`;
}

type TabKey = 'overview' | 'treatments' | 'appointments' | 'billing' | 'chart' | 'changes';

/// One patient's record at this clinic, built for handing a patient over: a
/// doctor who has never seen them should be able to tell, from the top of
/// this page, who they are, what happened last, what is still to do, what to
/// watch out for, and what they owe.
///
/// Tabs:
///   Overview      the handover: medical alerts, the last visit in full, the
///                 treatment plan, the next visit, the balance
///   Treatments    every treatment done, visit by visit (dental clinics)
///   Appointments  every visit, upcoming and past
///   Billing       every bill, with what was paid and what is owed
///   Chart & form  the patient information form and the tooth chart
///   Changes       who changed what on this chart, and when (admins only)
///
/// Shared by the doctor, front desk and admin apps. What each sees follows
/// useCanSeeClinicalNotes, which mirrors the database: clinicians get the
/// medical and consultation notes, the front desk the same page without
/// them. Every staff role sees the bills.
///
/// Navigation belongs to the app: pass [onOpenAppointment] where the app has
/// an appointment screen, [onOpenInvoice] where it has a bill screen, and
/// [onBook] where it can book. [canRecordVisits] offers to enter a visit
/// that happened but was never logged (the front desk and admins).
export function PatientHistoryScreen({
  patientId,
  onOpenAppointment,
  onOpenInvoice,
  onBook,
  canRecordVisits = false,
}: {
  patientId: string;
  onOpenAppointment?: (a: Appointment) => void;
  onOpenInvoice?: (invoiceId: string) => void;
  onBook?: () => void;
  canRecordVisits?: boolean;
}) {
  const qc = useQueryClient();
  const patientAsync = usePatientById(patientId);
  const historyAsync = usePatientHistory(patientId);
  const invoicesAsync = usePatientInvoices(patientId);
  const dental = useClinicChartsTeeth();
  const audited = useCanSeeAuditLog();
  const chartAsync = useDentalChart(patientId);
  const [tab, setTab] = useState<TabKey>('overview');

  const refresh = () => {
    for (const k of ['patient', 'patientHistory', 'chartNote', 'intake', 'dentalEntries', 'patientInvoices']) {
      void qc.invalidateQueries({ queryKey: [k] });
    }
  };

  if (!patientAsync.hasValue) {
    return (
      <Page title="Patient" scroll={false} back="/patients">
        {patientAsync.hasError ? (
          <ErrorView error={patientAsync.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['patient'] })} />
        ) : (
          <Loading />
        )}
      </Page>
    );
  }
  const patient = patientAsync.value;
  if (patient == null) {
    return (
      <Page title="Patient" back="/patients">
        <Text style={{ textAlign: 'center', marginTop: 48 }}>Patient not found.</Text>
      </Page>
    );
  }

  const chart = dental ? chartAsync.value ?? null : null;
  const visits = historyAsync.value ?? null;
  const invoices = invoicesAsync.value ?? null;
  const doneCount = chart?.entries.filter((e) => e.status === 'done').length;

  const keys: TabKey[] = ['overview', ...(dental ? (['treatments'] as const) : []), 'appointments', 'billing', 'chart', ...(audited ? (['changes'] as const) : [])];
  const labels: Record<TabKey, string> = {
    overview: 'Overview',
    treatments: doneCount == null ? 'Treatments' : `Treatments (${doneCount})`,
    appointments: visits == null ? 'Appointments' : `Appointments (${visits.length})`,
    billing: invoices == null ? 'Billing' : `Billing (${invoices.length})`,
    chart: dental ? 'Chart & form' : 'Information form',
    changes: 'Changes',
  };
  const current = keys.includes(tab) ? tab : 'overview';
  // Tabs by key, so a link on one tab can open another.
  const showTab = (k: string) => keys.includes(k as TabKey) && setTab(k as TabKey);

  const body: Record<TabKey, ReactNode> = {
    overview: <OverviewTab patient={patient} onOpenAppointment={onOpenAppointment} onShowTab={showTab} />,
    treatments: <TreatmentsTab patient={patient} onOpenAppointment={onOpenAppointment} />,
    appointments: <AppointmentsTab patient={patient} onOpenAppointment={onOpenAppointment} canRecordVisits={canRecordVisits} />,
    billing: <BillingTab patient={patient} onOpenInvoice={onOpenInvoice} />,
    chart: (
      <>
        <IntakeSection patient={patient} />
        <DentalChartSection patient={patient} />
      </>
    ),
    changes: null,
  };

  return (
    <Page
      title={patient.name}
      back="/patients"
      scroll={false}
      actions={<BarAction icon="refresh" label="Refresh" onPress={refresh} />}
      fab={onBook ? <FAB icon="event-available" label="Book visit" onPress={onBook} style={{ position: 'absolute', right: 16, bottom: 16 }} /> : undefined}
    >
      {current === 'changes' ? (
        <View style={{ flex: 1 }}>
          <Header patient={patient} visits={visits} invoices={invoices} plannedCount={chart?.plan.length ?? 0} onShowTab={showTab} />
          <TabBar keys={keys} labels={labels} value={current} onChange={setTab} />
          <View style={{ flex: 1 }}>
            <AuditLogView patientId={patient.id} />
          </View>
        </View>
      ) : (
        <ScrollView stickyHeaderIndices={[1]} contentContainerStyle={{ paddingBottom: 96 }}>
          <Header patient={patient} visits={visits} invoices={invoices} plannedCount={chart?.plan.length ?? 0} onShowTab={showTab} />
          <TabBar keys={keys} labels={labels} value={current} onChange={setTab} />
          <View style={{ padding: 16, width: '100%', maxWidth: ContentWidth.detail, alignSelf: 'center' }}>{body[current]}</View>
        </ScrollView>
      )}
    </Page>
  );
}

function TabBar({ keys, labels, value, onChange }: { keys: TabKey[]; labels: Record<TabKey, string>; value: TabKey; onChange: (k: TabKey) => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ backgroundColor: colors.surface }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ flexGrow: 1, justifyContent: 'center' }}>
        <View style={{ width: '100%', maxWidth: ContentWidth.detail }}>
          <Tabs scrollable value={value} onChange={onChange} tabs={keys.map((k) => ({ value: k, label: labels[k] }))} />
        </View>
      </ScrollView>
    </View>
  );
}

// ── Header: who, remarks, the numbers ───────────────────────────────────────

function Header({
  patient,
  visits,
  invoices,
  plannedCount,
  onShowTab,
}: {
  patient: Patient;
  visits: Appointment[] | null;
  invoices: import('../models/invoice').Invoice[] | null;
  plannedCount: number;
  onShowTab: (tab: string) => void;
}) {
  const { colors } = useAppTheme();
  const recallMonths = useCurrentClinic().value?.recallMonths ?? 6;
  const remarks = visits == null || invoices == null ? null : patientRemarks({ patient, visits, invoices, plannedCount, recallMonths });
  const dob = patient.dateOfBirth;
  const details: [IconName, string][] = [
    ...(patient.chartNumber != null ? [['folder', `Chart no. ${patient.chartNumber}`] as [IconName, string]] : []),
    ...(patient.phone !== '' ? [['phone', patient.phone] as [IconName, string]] : []),
    ...(patient.email !== '' ? [['email', patient.email] as [IconName, string]] : []),
    ...(dob != null
      ? [['cake', `Age ${patient.age} · born ${date(dob)}${patient.sex == null ? '' : ` · ${sexLabel[patient.sex]}`}`] as [IconName, string]]
      : []),
    ...(patient.address?.trim() ? [['place', patient.address] as [IconName, string]] : []),
    ...(patient.emergencyContactName?.trim()
      ? [
          [
            'contact-emergency',
            `Emergency: ${patient.emergencyContactName}${patient.emergencyContactPhone == null ? '' : ` · ${patient.emergencyContactPhone}`}`,
          ] as [IconName, string],
        ]
      : []),
  ];

  return (
    <View style={{ paddingHorizontal: 16, paddingTop: 16, paddingBottom: 8, width: '100%', maxWidth: ContentWidth.detail, alignSelf: 'center' }}>
      <View style={{ padding: 20, borderRadius: 20, backgroundColor: colors.surfaceContainerLow }}>
        <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 16 }}>
          <Avatar label={patient.initials} size={60} />
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={{ fontWeight: '700', fontSize: 18 }}>{patient.name}</Text>
            <View style={{ height: 4 }} />
            {details.length === 0 && <DetailLine icon="info-outline" text="No contact details on file" />}
            {/* Two columns of details once there is room. */}
            <CardColumns minItemWidth={280} maxColumns={2} spacing={12} runSpacing={0}>
              {details.map(([icon, text]) => (
                <DetailLine key={text} icon={icon} text={text} />
              ))}
            </CardColumns>
            {remarks != null && remarks.flags.size > 0 && (
              <View style={{ marginTop: 10 }}>
                <RemarkChips flags={remarks.flags} attention={remarks.attention} />
              </View>
            )}
          </View>
        </View>
        {visits != null && <Stats visits={visits} invoices={invoices} onShowTab={onShowTab} />}
      </View>
    </View>
  );
}

function Stats({
  visits,
  invoices,
  onShowTab,
}: {
  /// Newest first, as the history comes.
  visits: Appointment[];
  invoices: import('../models/invoice').Invoice[] | null;
  onShowTab: (tab: string) => void;
}) {
  const { colors, dark } = useAppTheme();
  const now = Date.now();
  const completed = visits.filter((a) => a.status === 'completed');
  const upcoming = visits.filter((a) => a.dateTime.getTime() > now && holdsTime(a.status));
  const next = upcoming.length === 0 ? null : upcoming[upcoming.length - 1].dateTime;
  const first = completed.length === 0 ? null : completed[completed.length - 1].dateTime;
  const last = completed.length === 0 ? null : completed[0].dateTime;
  const owed = invoices?.filter((v) => v.status === 'issued').reduce((s, v) => s + v.balance, 0) ?? null;
  return (
    <View style={{ marginTop: 16, paddingVertical: 6, borderRadius: 14, backgroundColor: colors.surface }}>
      <CardColumns minItemWidth={120} maxColumns={5} spacing={0} runSpacing={0}>
        <Stat label="First visit" value={first == null ? '—' : date(first)} onPress={() => onShowTab('appointments')} />
        <Stat
          label="Last visit"
          value={last == null ? '—' : date(last)}
          caption={last == null ? undefined : relativeDay(last)}
          onPress={() => onShowTab('appointments')}
        />
        <Stat
          label="Next visit"
          value={next == null ? 'None booked' : date(next)}
          caption={next == null ? undefined : relativeDay(next)}
          onPress={() => onShowTab('appointments')}
        />
        <Stat label="Visits" value={`${completed.length}`} onPress={() => onShowTab('appointments')} />
        <Stat
          label="Balance"
          value={owed == null ? '…' : owed > 0 ? formatPeso(owed) : 'None'}
          color={(owed ?? 0) > 0 ? remarkColor('balance', dark) : undefined}
          onPress={() => onShowTab('billing')}
        />
      </CardColumns>
    </View>
  );
}

function Stat({ label, value, caption, color, onPress }: { label: string; value: string; caption?: string; color?: string; onPress?: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={{ paddingVertical: 8, paddingHorizontal: 4, borderRadius: 10, alignItems: 'center' }}>
      <Text style={{ fontWeight: '700', fontSize: 15, color: color ?? colors.primary, textAlign: 'center' }}>{value}</Text>
      <Text style={{ fontSize: 11, color: colors.onSurfaceVariant, textAlign: 'center' }}>{caption == null ? label : `${label} · ${caption}`}</Text>
    </Pressable>
  );
}

// ── Overview: the handover ──────────────────────────────────────────────────

function OverviewTab({
  patient,
  onShowTab,
  onOpenAppointment: open,
}: {
  patient: Patient;
  onShowTab: (tab: string) => void;
  onOpenAppointment?: (a: Appointment) => void;
}) {
  const qc = useQueryClient();
  const historyAsync = usePatientHistory(patient.id);
  const showClinical = useCanSeeClinicalNotes().value ?? false;
  return (
    <AsyncView value={historyAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['patientHistory'] })}>
      {(visits) => {
        const now = Date.now();
        const over = visits.filter((a) => a.dateTime.getTime() <= now && (a.status === 'completed' || a.status === 'no_show'));
        const lastVisit = over.length === 0 ? null : over[0];
        const upcoming = visits.filter((a) => a.dateTime.getTime() > now && holdsTime(a.status)).reverse();
        const lastCard =
          lastVisit == null ? (
            <Muted text="No visit completed at this clinic yet." />
          ) : (
            <LastVisitCard appointment={lastVisit} showClinical={showClinical} onPress={open && (() => open(lastVisit))} />
          );
        const nextList =
          upcoming.length === 0 ? (
            <Muted text="Nothing booked." />
          ) : (
            upcoming.slice(0, 2).map((a) => (
              <View key={a.id} style={{ marginBottom: 8 }}>
                <VisitTile appointment={a} onPress={open && (() => open(a))} />
              </View>
            ))
          );
        return (
          <SplitColumns
            start={
              <>
                <SectionTitle text="Last visit" />
                {lastCard}
                <TreatmentPlan patient={patient} upcoming={upcoming} />
                <SectionTitle text="Next visit" />
                {nextList}
                {over.length > 1 && (
                  <>
                    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                      <View style={{ flex: 1 }}>
                        <SectionTitle text="Before that" />
                      </View>
                      <Button onPress={() => onShowTab('appointments')}>All appointments</Button>
                    </View>
                    {over.slice(1, 4).map((a) => (
                      <View key={a.id} style={{ marginBottom: 8 }}>
                        <VisitTile appointment={a} showClinical={showClinical} onPress={open && (() => open(a))} />
                      </View>
                    ))}
                  </>
                )}
              </>
            }
            end={
              <>
                <MedicalAlerts patientId={patient.id} onShowTab={onShowTab} />
                <ChartNoteSection patient={patient} />
                <BalanceCard patientId={patient.id} onShowTab={onShowTab} />
              </>
            }
            // On a phone: what to watch out for before the history.
            narrow={
              <>
                <MedicalAlerts patientId={patient.id} onShowTab={onShowTab} />
                <SectionTitle text="Last visit" />
                {lastCard}
                <TreatmentPlan patient={patient} upcoming={upcoming} />
                <SectionTitle text="Next visit" />
                {nextList}
                <View style={{ height: 8 }} />
                <ChartNoteSection patient={patient} />
                <BalanceCard patientId={patient.id} onShowTab={onShowTab} />
              </>
            }
          />
        );
      }}
    </AsyncView>
  );
}

function SectionTitle({ text }: { text: string }) {
  return (
    <Text variant="titleSmall" style={{ fontWeight: '700', marginTop: 4, marginBottom: 8 }}>
      {text}
    </Text>
  );
}

function Muted({ text }: { text: string }) {
  const { colors } = useAppTheme();
  return <Text style={{ marginBottom: 16, color: colors.outline }}>{text}</Text>;
}

/// The last visit in full: who, what, the consultation note, the note to the
/// patient, and every tooth touched.
function LastVisitCard({ appointment: a, showClinical, onPress }: { appointment: Appointment; showClinical: boolean; onPress?: () => void }) {
  const { colors } = useAppTheme();
  const chartsTeeth = useClinicChartsTeeth();
  const chart = useDentalChart(a.patient.id).value;
  const [numbering] = useToothNumbering();
  const entries = chartsTeeth && chart ? chart.atVisit(a.id) : [];
  const having = (s: DentalEntryStatus) => entries.filter((e) => e.status === s);
  const groups: [string, DentalEntry[]][] = [
    ['Done', having('done')],
    ['Found', having('existing')],
    ['Planned', having('planned')],
  ];
  return (
    <AppCard onPress={onPress} padding={16} style={{ marginBottom: 16 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <Text style={{ flex: 1, fontWeight: '700', fontSize: 16 }}>{a.service}</Text>
        <StatusBadge status={a.status} small />
      </View>
      <Text style={{ marginTop: 2, fontSize: 13, color: colors.onSurfaceVariant }}>
        {date(a.dateTime)} ({relativeDay(a.dateTime)}) · Dr. {a.doctor.name}
      </Text>
      {a.status === 'no_show' && <Text style={{ marginTop: 8, color: colors.error }}>The patient did not come to this visit.</Text>}
      {showClinical && (
        <View style={{ marginTop: 12 }}>
          <LabeledText icon="assignment" label="Consultation note" text={a.visitNote?.body ?? null} empty="No consultation note written." />
        </View>
      )}
      {a.patientNote != null && (
        <View style={{ marginTop: 10 }}>
          <LabeledText icon="chat-bubble-outline" label="Note to the patient" text={a.patientNote} />
        </View>
      )}
      {groups
        .filter(([, list]) => list.length > 0)
        .map(([title, list]) => (
          <View key={title} style={{ marginTop: 10 }}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.onSurfaceVariant }}>{title}</Text>
            {list.map((e) => (
              <DentalEntryTile key={e.id} entry={e} numbering={numbering} />
            ))}
          </View>
        ))}
      {onPress != null && <Text style={{ alignSelf: 'flex-end', color: colors.primary, fontWeight: '600' }}>Open visit ›</Text>}
    </AppCard>
  );
}

function LabeledText({ icon, label, text, empty }: { icon: IconName; label: string; text: string | null; empty?: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 8 }}>
      <Icon name={icon} size={16} color={colors.outline} />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 12, fontWeight: '700', color: colors.onSurfaceVariant }}>{label}</Text>
        <Text style={text == null ? { color: colors.outline, fontStyle: 'italic' } : undefined}>{text ?? empty ?? ''}</Text>
      </View>
    </View>
  );
}

/// What is planned and not done yet, and whether it is booked. Dental.
function TreatmentPlan({ patient, upcoming }: { patient: Patient; upcoming: Appointment[] }) {
  const { colors } = useAppTheme();
  const chartsTeeth = useClinicChartsTeeth();
  const chart = useDentalChart(patient.id).value;
  const [numbering] = useToothNumbering();
  if (!chartsTeeth || chart == null) return null;
  const plan = chart.plan;
  return (
    <View>
      <SectionTitle text={`Treatment plan${plan.length === 0 ? '' : ` (${plan.length})`}`} />
      {plan.length === 0 ? (
        <Muted text="Nothing planned." />
      ) : (
        <AppCard style={{ marginBottom: 16, paddingHorizontal: 16, paddingVertical: 8 }}>
          {upcoming.length === 0 && (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingVertical: 4 }}>
              <Icon name="warning-amber" size={16} color={colors.error} />
              <Text style={{ color: colors.error, fontWeight: '600' }}>Not booked yet</Text>
            </View>
          )}
          {plan.map((e) => (
            <DentalEntryTile key={e.id} entry={e} numbering={numbering} />
          ))}
        </AppCard>
      )}
    </View>
  );
}

function alertLines(i: PatientIntake): [string, string][] {
  // The labels already end with the "other" answer, so it appears once.
  const allergies = i.allergyLabels.map((l) => l.trim()).filter((l) => l !== '').join(', ');
  const conditions = i.conditionLabels.map((l) => l.trim()).filter((l) => l !== '').join(', ');
  return [
    ...(allergies !== '' ? [['Allergies', allergies] as [string, string]] : []),
    ...(conditions !== '' ? [['Conditions', conditions] as [string, string]] : []),
    ...(i.takesMedications ? [['Medicines', i.medications?.trim() ? i.medications.trim() : 'Yes, not listed'] as [string, string]] : []),
    ...(i.underTreatment ? [['Under treatment', i.treatmentDetails?.trim() ? i.treatmentDetails.trim() : 'Yes'] as [string, string]] : []),
    ...(i.pregnant === true ? [['Pregnant', 'Yes'] as [string, string]] : []),
    ...(i.nursing === true ? [['Nursing', 'Yes'] as [string, string]] : []),
  ];
}

/// Allergies, conditions, medicines and the like from the information form,
/// on top because they change what anyone may do.
function MedicalAlerts({ patientId, onShowTab }: { patientId: string; onShowTab: (tab: string) => void }) {
  const { colors } = useAppTheme();
  const intakeAsync = useIntake(patientId);
  const intake = intakeAsync.value;
  if (intakeAsync.isLoading && intake == null) return null;
  if (intake == null) {
    return (
      <AppCard style={{ marginBottom: 12 }}>
        <ListTile
          leading={<Icon name="assignment-late" color={colors.outline} />}
          title="No information form on file"
          subtitle="Allergies and conditions are unknown."
          trailing={<Button onPress={() => onShowTab('chart')}>Fill in</Button>}
        />
      </AppCard>
    );
  }
  const lines = alertLines(intake);
  const alert = lines.length > 0;
  const color = alert ? colors.error : colors.primary;
  return (
    <View
      style={{
        marginBottom: 12,
        padding: 16,
        borderRadius: 16,
        backgroundColor: alert ? withAlpha(colors.errorContainer, 90 / 255) : colors.surfaceContainerLow,
        borderWidth: 1,
        borderColor: withAlpha(color, (alert ? 90 : 40) / 255),
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <Icon name={alert ? 'medical-information' : 'verified-user'} size={18} color={color} />
        <Text style={{ flex: 1, fontWeight: '700', color }}>{alert ? 'Medical alerts' : 'No medical alerts'}</Text>
        <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>Form {date(intake.updatedAt)}</Text>
      </View>
      {lines.map(([label, text]) => (
        <Text key={label} style={{ marginTop: 8 }}>
          <Text style={{ fontWeight: '700' }}>{label}: </Text>
          {text}
        </Text>
      ))}
      {!alert && <Text style={{ marginTop: 6, color: colors.onSurfaceVariant }}>No allergies, conditions or medicines declared.</Text>}
    </View>
  );
}

function BalanceCard({ patientId, onShowTab }: { patientId: string; onShowTab: (tab: string) => void }) {
  const { colors, dark } = useAppTheme();
  const bills = usePatientInvoices(patientId).value;
  if (bills == null) return null;
  const open = bills.filter((v) => v.status === 'issued' && v.balance > 0);
  const owed = open.reduce((s, v) => s + v.balance, 0);
  const drafts = bills.filter((v) => v.isDraft).length;
  const color = owed > 0 ? remarkColor('balance', dark) : colors.primary;
  return (
    <AppCard style={{ marginBottom: 12 }}>
      <ListTile
        onPress={() => onShowTab('billing')}
        leading={<Icon name="account-balance-wallet" color={color} />}
        title={<Text style={{ fontWeight: '700', color }}>{owed > 0 ? `${formatPeso(owed)} owed` : 'Nothing owed'}</Text>}
        subtitle={[
          ...(open.length > 0 ? [`${open.length} unpaid bill${open.length === 1 ? '' : 's'}`] : []),
          ...(drafts > 0 ? [`${drafts} draft${drafts === 1 ? '' : 's'} not issued`] : []),
          ...(open.length === 0 && drafts === 0 ? [`${bills.length} bill${bills.length === 1 ? '' : 's'} on file`] : []),
        ].join(' · ')}
        trailing={<Icon name="chevron-right" />}
      />
    </AppCard>
  );
}

// ── Treatments done (dental) ────────────────────────────────────────────────

/// Every treatment done, grouped by the visit it was done at, newest first.
function TreatmentsTab({ patient, onOpenAppointment: open }: { patient: Patient; onOpenAppointment?: (a: Appointment) => void }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const chartAsync = useDentalChart(patient.id);
  const visits = usePatientHistory(patient.id).value ?? [];
  const [numbering] = useToothNumbering();
  const showClinical = useCanSeeClinicalNotes().value ?? false;
  const byId = new Map(visits.map((a) => [a.id, a]));
  return (
    <AsyncView value={chartAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['dentalEntries'] })}>
      {(chart) => {
        const done = chart.entries.filter((e) => e.status === 'done');
        if (done.length === 0) {
          return (
            <View style={{ paddingTop: 24, alignItems: 'center' }}>
              <Muted text="No treatment recorded as done yet." />
            </View>
          );
        }
        // Visit by visit. A treatment done always names its visit; one whose
        // visit was deleted is kept under "Visit not on file".
        const groups = new Map<string | null, DentalEntry[]>();
        for (const e of done) {
          const list = groups.get(e.appointmentId) ?? [];
          list.push(e);
          groups.set(e.appointmentId, list);
        }
        const when = (id: string | null, list: DentalEntry[]) =>
          byId.get(id ?? '')?.dateTime ??
          new Date(Math.max(...list.map((e) => (e.updatedAt ?? e.createdAt ?? new Date(0)).getTime())));
        const ordered = [...groups.entries()].sort((a, b) => when(b[0], b[1]).getTime() - when(a[0], a[1]).getTime());
        return (
          <View>
            <Text style={{ color: colors.onSurfaceVariant }}>
              {done.length} treatment{done.length === 1 ? '' : 's'} over {ordered.length} visit{ordered.length === 1 ? '' : 's'}
            </Text>
            <View style={{ height: 12 }} />
            {ordered.map(([id, list]) => {
              const visit = byId.get(id ?? '') ?? null;
              return (
                <TreatmentVisit
                  key={id ?? 'none'}
                  visit={visit}
                  entries={[...list].sort((a, b) => a.tooth - b.tooth)}
                  date={when(id, list)}
                  numbering={numbering}
                  showClinical={showClinical}
                  onPress={visit == null || open == null ? undefined : () => open(visit)}
                />
              );
            })}
          </View>
        );
      }}
    </AsyncView>
  );
}

function TreatmentVisit({
  visit: v,
  entries,
  date: d,
  numbering,
  showClinical,
  onPress,
}: {
  visit: Appointment | null;
  entries: DentalEntry[];
  date: Date;
  numbering: import('../models/dental_chart').ToothNumbering;
  showClinical: boolean;
  onPress?: () => void;
}) {
  const { colors } = useAppTheme();
  const note = v?.visitNote;
  // A timeline: a dot per visit, joined by a line.
  return (
    <View style={{ flexDirection: 'row', alignItems: 'stretch' }}>
      <View style={{ width: 24, alignItems: 'center' }}>
        <View style={{ height: 18 }} />
        <View style={{ width: 12, height: 12, borderRadius: 6, backgroundColor: colors.primary }} />
        <View style={{ flex: 1, width: 2, backgroundColor: colors.outlineVariant }} />
      </View>
      <View style={{ width: 8 }} />
      <View style={{ flex: 1, paddingBottom: 12 }}>
        <AppCard onPress={onPress} style={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 8 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            <Text style={{ flex: 1, fontWeight: '700' }}>{v == null ? 'Visit not on file' : `${date(d)} · ${v.service}`}</Text>
            {onPress != null && <Icon name="chevron-right" color={colors.outline} />}
          </View>
          {v != null && (
            <Text style={{ fontSize: 13, color: colors.onSurfaceVariant }}>
              Dr. {v.doctor.name} · {relativeDay(d)}
            </Text>
          )}
          {entries.map((e) => (
            <DentalEntryTile key={e.id} entry={e} numbering={numbering} />
          ))}
          {showClinical && note != null && <NoteLine icon="assignment" text={note.body} />}
        </AppCard>
      </View>
    </View>
  );
}

// ── Appointments ────────────────────────────────────────────────────────────

function AppointmentsTab({
  patient,
  canRecordVisits,
  onOpenAppointment,
}: {
  patient: Patient;
  canRecordVisits: boolean;
  onOpenAppointment?: (a: Appointment) => void;
}) {
  const qc = useQueryClient();
  const historyAsync = usePatientHistory(patient.id);
  const showClinical = useCanSeeClinicalNotes().value ?? false;
  const recordVisit = useRecordVisitSheet();
  return (
    <AsyncView value={historyAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['patientHistory'] })}>
      {(visits) => (
        <Visits
          visits={visits}
          showClinical={showClinical}
          onOpen={onOpenAppointment}
          onRecord={canRecordVisits ? () => void recordVisit(patient) : undefined}
        />
      )}
    </AsyncView>
  );
}

function Visits({
  visits,
  showClinical,
  onOpen: open,
  onRecord,
}: {
  /// Newest first.
  visits: Appointment[];
  showClinical: boolean;
  onOpen?: (a: Appointment) => void;
  onRecord?: () => void;
}) {
  const { colors } = useAppTheme();
  const now = Date.now();
  const isUpcoming = (a: Appointment) => a.dateTime.getTime() > now && holdsTime(a.status);
  const upcoming = visits.filter(isUpcoming).reverse();
  const past = visits.filter((a) => !isUpcoming(a));
  const missed = past.filter((a) => a.status === 'no_show').length;
  const cancelled = past.filter((a) => a.status === 'cancelled').length;
  const tile = (a: Appointment) => (
    <View key={a.id} style={{ marginBottom: 8 }}>
      <VisitTile appointment={a} showClinical={showClinical} onPress={open && (() => open(a))} />
    </View>
  );
  return (
    <View>
      {upcoming.length > 0 && (
        <>
          <Heading text="Upcoming" />
          {upcoming.map(tile)}
        </>
      )}
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <View style={{ flex: 1 }}>
          <Heading text="Visit history" />
        </View>
        {onRecord != null && (
          <Button icon="edit-note" onPress={onRecord}>
            Manually add visit
          </Button>
        )}
      </View>
      {(missed > 0 || cancelled > 0) && (
        <Text style={{ marginBottom: 8, fontSize: 12, color: colors.onSurfaceVariant }}>
          {[...(missed > 0 ? [`${missed} missed`] : []), ...(cancelled > 0 ? [`${cancelled} cancelled`] : [])].join(' · ')}
        </Text>
      )}
      {past.length === 0 ? <Text style={{ paddingVertical: 8, color: colors.outline }}>No past visits yet.</Text> : past.map(tile)}
    </View>
  );
}

function Heading({ text }: { text: string }) {
  return (
    <Text variant="titleMedium" style={{ fontWeight: '700', paddingVertical: 8 }}>
      {text}
    </Text>
  );
}

// ── Billing ─────────────────────────────────────────────────────────────────

function BillingTab({ patient, onOpenInvoice: open }: { patient: Patient; onOpenInvoice?: (id: string) => void }) {
  const { colors, dark } = useAppTheme();
  const qc = useQueryClient();
  const billsAsync = usePatientInvoices(patient.id);
  const statement = usePrintStatement();
  return (
    <AsyncView value={billsAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['patientInvoices'] })}>
      {(bills) => {
        if (bills.length === 0) {
          return (
            <View style={{ paddingTop: 24, alignItems: 'center' }}>
              <Muted text="No bills yet." />
            </View>
          );
        }
        const counted = bills.filter((v) => v.status === 'issued' || v.status === 'paid');
        const billed = counted.reduce((s, v) => s + v.total, 0);
        const paid = counted.reduce((s, v) => s + v.amountPaid, 0);
        const owed = counted.reduce((s, v) => s + v.balance, 0);
        return (
          <View>
            <View style={{ flexDirection: 'row', paddingVertical: 6, borderRadius: 14, backgroundColor: colors.surfaceContainerLow }}>
              <View style={{ flex: 1 }}>
                <Stat label="Billed" value={formatPeso(billed)} />
              </View>
              <View style={{ flex: 1 }}>
                <Stat label="Paid" value={formatPeso(paid)} />
              </View>
              <View style={{ flex: 1 }}>
                <Stat label="Balance" value={owed > 0 ? formatPeso(owed) : 'None'} color={owed > 0 ? remarkColor('balance', dark) : undefined} />
              </View>
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', paddingLeft: 4, paddingTop: 8, paddingBottom: 8 }}>
              <Text style={{ flex: 1, fontSize: 12, color: colors.onSurfaceVariant }}>Drafts and voided bills are not counted.</Text>
              <Button icon="print" onPress={() => statement.choose(patient, bills)}>
                Print statement
              </Button>
            </View>
            {bills.map((v) => (
              <InvoiceTile key={v.id} invoice={v} onPress={open && (() => open(v.id))} />
            ))}
          </View>
        );
      }}
    </AsyncView>
  );
}

// ── On a visit's page ───────────────────────────────────────────────────────

/// A patient's visits before [appointment], for the doctor to glance at
/// during the consult: the latest few, and a link to the whole history.
///
/// Only on a visit still open. On one that is over it would chain: an old
/// visit listing older ones, each listing older still, every tap a page
/// deeper. The full history is the place to browse those.
export function PreviousVisitsSection({
  appointment,
  limit = 3,
  onOpenHistory,
  onOpenAppointment: open,
}: {
  appointment: Appointment;
  limit?: number;
  onOpenHistory?: () => void;
  onOpenAppointment?: (a: Appointment) => void;
}) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const historyAsync = usePatientHistory(appointment.patient.id);
  const showClinical = useCanSeeClinicalNotes().value ?? false;
  if (!isOpenStatus(appointment.status)) return null;
  return (
    <View style={{ marginBottom: 12 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>Previous visits</Text>
        {onOpenHistory != null && <Button onPress={onOpenHistory}>Full history</Button>}
      </View>
      <AsyncView value={historyAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['patientHistory'] })}>
        {(visits) => {
          const earlier = visits
            .filter((a) => a.id !== appointment.id && a.dateTime.getTime() < appointment.dateTime.getTime() && holdsTime(a.status))
            .slice(0, limit);
          if (earlier.length === 0) return <Text style={{ paddingVertical: 8, color: colors.outline }}>No earlier visits at this clinic.</Text>;
          return (
            <View>
              {earlier.map((a) => (
                <View key={a.id} style={{ marginBottom: 8 }}>
                  <VisitTile appointment={a} showClinical={showClinical} onPress={open && (() => open(a))} />
                </View>
              ))}
            </View>
          );
        }}
      </AsyncView>
    </View>
  );
}

/// One appointment in a patient's history.
///
/// With [showClinical] it also shows the consultation note — pass true only
/// for a clinician, and only for an appointment fetched with its visit note.
export function VisitTile({ appointment: a, showClinical = false, onPress }: { appointment: Appointment; showClinical?: boolean; onPress?: () => void }) {
  const { colors } = useAppTheme();
  return (
    <AppCard onPress={onPress} padding={14}>
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 12 }}>
        <DateBlock date={a.dateTime} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Text style={{ flex: 1, fontWeight: '600', fontSize: 15 }}>{a.service}</Text>
            <StatusBadge status={a.status} small />
          </View>
          <Text style={{ marginTop: 2, fontSize: 13, color: colors.onSurfaceVariant }}>
            Dr. {a.doctor.name} · {format(a.dateTime, 'h:mm a')}
          </Text>
          {showClinical && a.visitNote != null && <NoteLine icon="assignment" text={a.visitNote.body} />}
          {a.patientNote != null && <NoteLine icon="chat-bubble-outline" text={a.patientNote} />}
          <VisitDentalLine patientId={a.patient.id} appointmentId={a.id} />
        </View>
        {onPress != null && (
          <View style={{ paddingLeft: 4, paddingTop: 8 }}>
            <Icon name="chevron-right" color={colors.outline} />
          </View>
        )}
      </View>
    </AppCard>
  );
}

function DateBlock({ date: d }: { date: Date }) {
  const { colors } = useAppTheme();
  const c = colors.onPrimaryContainer;
  return (
    <View style={{ width: 52, paddingVertical: 6, borderRadius: 10, backgroundColor: colors.primaryContainer, alignItems: 'center' }}>
      <Text style={{ fontSize: 11, color: c }}>{format(d, 'MMM')}</Text>
      <Text style={{ fontSize: 18, fontWeight: '700', color: c }}>{d.getDate()}</Text>
      <Text style={{ fontSize: 10, color: c }}>{d.getFullYear()}</Text>
    </View>
  );
}

function DetailLine({ icon, text }: { icon: IconName; text: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, paddingTop: 2 }}>
      <Icon name={icon} size={14} color={colors.onSurfaceVariant} />
      <Text style={{ flex: 1, fontSize: 13, color: colors.onSurfaceVariant }}>{text}</Text>
    </View>
  );
}

function NoteLine({ icon, text }: { icon: IconName; text: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 6, paddingTop: 6 }}>
      <Icon name={icon} size={14} color={colors.outline} />
      <Text numberOfLines={3} style={{ flex: 1, fontSize: 13 }}>
        {text}
      </Text>
    </View>
  );
}
