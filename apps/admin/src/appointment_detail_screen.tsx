import {
  type Appointment,
  type AppointmentStatus,
  AsyncView,
  ChartNoteSection,
  ContentWidth,
  DentalChartSection,
  DoctorAvatar,
  Icon,
  type IconName,
  Page,
  PatientNoteSection,
  PreviousVisitsSection,
  SplitColumns,
  VisitBillSection,
  VisitHeader,
  VisitNoteSection,
  refreshAppointments,
  staffCanCancel,
  useAppTheme,
  useAppointmentById,
  useClinicNav,
  useCompleteVisitSheet,
  useRescheduleSheet,
  useStatusActions,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

export function AdminAppointmentDetailScreen({ appointmentId }: { appointmentId: string }) {
  const qc = useQueryClient();
  const async = useAppointmentById(appointmentId);
  return (
    <Page title="Appointment Details" back="/schedule" maxWidth={ContentWidth.detail}>
      <AsyncView value={async} padded onRetry={() => void refreshAppointments(qc)}>
        {(a) => (a == null ? <Text style={{ textAlign: 'center', padding: 32 }}>Not found.</Text> : <Details appointment={a} />)}
      </AsyncView>
    </Page>
  );
}

function Details({ appointment: a }: { appointment: Appointment }) {
  const { colors } = useAppTheme();
  const nav = useClinicNav();
  const status = useStatusActions();
  const completeVisit = useCompleteVisitSheet();
  const reschedule = useRescheduleSheet();
  const openHistory = () => nav.open(`/patients/${a.patient.id}`);

  const header = (
    <View style={{ marginBottom: 16 }}>
      <VisitHeader appointment={a} who={`${a.patient.name} · Dr. ${a.doctor.name}`} />
    </View>
  );
  const patient = (
    <Section
      title="Patient"
      action={
        <Button icon="history" compact onPress={openHistory}>
          History
        </Button>
      }
    >
      <Row2 icon="person-outline" label="Name" value={a.patient.name} />
      <Row2 icon="phone" label="Phone" value={a.patient.phone} />
      <Row2 icon="email" label="Email" value={a.patient.email} />
      {a.patient.age != null && <Row2 icon="cake" label="Age" value={`${a.patient.age} years old`} />}
    </Section>
  );
  const doctor = (
    <Section title="Doctor">
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
        <DoctorAvatar doctor={a.doctor} radius={28} />
        <View>
          <Text style={{ fontWeight: '600' }}>Dr. {a.doctor.name}</Text>
          <Text style={{ color: colors.onSurfaceVariant }}>{a.doctor.specialty}</Text>
        </View>
      </View>
    </Section>
  );
  // Full width under the two columns on a wide screen, so the teeth are
  // big enough to tap on a tablet.
  const chart = <DentalChartSection patient={a.patient} appointment={a} />;
  // Clinical notes and history — admins are clinicians for this purpose
  // (the clinic owner is often a doctor).
  const clinical = [
    <ChartNoteSection key="chart-note" patient={a.patient} />,
    <PreviousVisitsSection key="previous" appointment={a} onOpenHistory={openHistory} onOpenAppointment={(v) => nav.open(`/appointments/${v.id}`)} />,
    <VisitNoteSection key="visit-note" appointment={a} />,
    <PatientNoteSection key="patient-note" appointment={a} />,
  ];
  const bill = (
    <View style={{ marginBottom: 12 }}>
      <VisitBillSection appointment={a} onOpenInvoice={(id) => nav.push(`/billing/${id}`)} />
    </View>
  );

  // The visit's next steps. An admin may take any of them.
  const step = (to: AppointmentStatus, icon: IconName, label: string, done: string) => (
    <Button key={label} mode="contained" icon={icon} onPress={() => void status.change(a, to, done)}>
      {label}
    </Button>
  );
  const actionButtons = [
    a.status === 'pending' && step('confirmed', 'check-circle-outline', 'Confirm appointment', 'Appointment confirmed'),
    a.status === 'confirmed' && step('arrived', 'how-to-reg', 'Check in', 'Checked in'),
    (a.status === 'confirmed' || a.status === 'arrived') && step('in_consultation', 'play-arrow', 'Start consultation', 'Consultation started'),
    // Marking done bills the services performed; the bill opens next.
    a.status === 'completed' && (
      <Button key="services" mode="outlined" icon="checklist" onPress={() => void completeVisit(a)}>
        Services done
      </Button>
    ),
    (a.status === 'arrived' || a.status === 'in_consultation') && (
      <Button
        key="done"
        mode="contained"
        icon="task-alt"
        onPress={async () => {
          const id = await completeVisit(a);
          if (id != null && id !== '') nav.push(`/billing/${id}`);
        }}
      >
        Mark done
      </Button>
    ),
    a.status === 'confirmed' && a.dateTime.getTime() <= Date.now() && (
      <Button key="no-show" mode="outlined" icon="person-off" onPress={() => void status.change(a, 'no_show', 'Marked as a no-show')}>
        Mark as no-show
      </Button>
    ),
    a.canReschedule && (
      <Button key="move" mode="outlined" icon="edit-calendar" onPress={() => void reschedule(a, true)}>
        Reschedule
      </Button>
    ),
    staffCanCancel(a.status) && (
      <Button
        key="cancel"
        mode="outlined"
        icon="cancel"
        textColor={colors.error}
        style={{ borderColor: colors.error }}
        onPress={async () => {
          if (await status.confirmAndCancel(a, a.patient.name)) nav.back('/schedule');
        }}
      >
        Cancel appointment
      </Button>
    ),
  ].filter(Boolean);
  const actions = actionButtons.length === 0 ? null : <View style={{ gap: 8 }}>{actionButtons}</View>;

  return (
    <SplitColumns
      startFlex={2}
      endFlex={3}
      // On a phone, the page reads top to bottom; on a wide screen the visit
      // and its next steps sit on the left, the clinical record beside them.
      narrow={
        <>
          {header}
          {patient}
          {doctor}
          {clinical.slice(0, 2)}
          {chart}
          {clinical.slice(2)}
          {bill}
          {actions}
        </>
      }
      // The next step right under the header, above the fold on a tablet
      // held sideways.
      start={
        <>
          {header}
          {actions != null && <View style={{ marginBottom: 16 }}>{actions}</View>}
          {patient}
          {doctor}
          {bill}
        </>
      }
      end={<>{clinical}</>}
      below={chart}
    />
  );
}

function Section({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', minHeight: 24, marginBottom: 8 }}>
        <Text style={{ flex: 1, fontWeight: '600', fontSize: 12, color: colors.onSurfaceVariant }}>{title}</Text>
        {action}
      </View>
      {children}
    </View>
  );
}

function Row2({ icon, label, value }: { icon: IconName; label: string; value: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 4, gap: 8 }}>
      <Icon name={icon} size={16} color={colors.primary} />
      <Text style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>{label}: </Text>
      {value.trim() === '' ? (
        <Text style={{ flex: 1, color: colors.onSurfaceVariant, fontStyle: 'italic', fontSize: 13 }}>Not on file</Text>
      ) : (
        <Text selectable style={{ flex: 1, fontWeight: '500' }}>
          {value}
        </Text>
      )}
    </View>
  );
}
