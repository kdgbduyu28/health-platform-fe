import {
  type Appointment,
  AsyncView,
  ChartNoteSection,
  ContentWidth,
  DentalChartSection,
  Page,
  PatientNoteSection,
  PreviousVisitsSection,
  SplitColumns,
  VisitHeader,
  VisitNoteSection,
  refreshAppointments,
  useAppTheme,
  useAppointmentById,
  useClinicNav,
  useCompleteVisitSheet,
  useStatusActions,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

export function DoctorAppointmentDetailScreen({ appointmentId }: { appointmentId: string }) {
  const qc = useQueryClient();
  const async = useAppointmentById(appointmentId);
  return (
    <Page title="Patient Appointment" back="/schedule" maxWidth={ContentWidth.detail}>
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
  const patient = a.patient;
  const openHistory = () => nav.open(`/patients/${patient.id}`);

  const header = (
    <View style={{ marginBottom: 16 }}>
      <VisitHeader appointment={a} who={patient.name} />
    </View>
  );
  const patientCard = (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <Text style={{ flex: 1, fontWeight: '600', fontSize: 12, color: colors.onSurfaceVariant }}>Patient</Text>
        <Button icon="history" compact onPress={openHistory}>
          History
        </Button>
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
        <View
          style={{
            width: 56,
            height: 56,
            borderRadius: 28,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: colors.secondaryContainer,
          }}
        >
          <Text style={{ fontSize: 20, fontWeight: '700', color: colors.onSecondaryContainer }}>{patient.initials}</Text>
        </View>
        <View style={{ flex: 1 }}>
          <Text style={{ fontWeight: '600', fontSize: 16 }}>{patient.name}</Text>
          <Text style={{ color: colors.onSurfaceVariant }}>
            {patient.phone !== '' ? patient.phone : patient.email !== '' ? patient.email : 'No contact info'}
          </Text>
          {patient.age != null && <Text style={{ color: colors.onSurfaceVariant }}>Age {patient.age}</Text>}
        </View>
      </View>
    </View>
  );
  // Full width under the two columns on a wide screen, so the teeth are
  // big enough to tap on a tablet.
  const chart = <DentalChartSection key="chart" patient={patient} appointment={a} />;
  // What the consult needs, in the order it is needed: what is on file,
  // what happened last time, the teeth (at a dental clinic), then today's
  // notes.
  const clinical = [
    <ChartNoteSection key="chart-note" patient={patient} />,
    <PreviousVisitsSection
      key="previous"
      appointment={a}
      onOpenHistory={openHistory}
      onOpenAppointment={(v) => nav.open(`/appointments/${v.id}`)}
    />,
    <VisitNoteSection key="visit-note" appointment={a} />,
    <PatientNoteSection key="patient-note" appointment={a} />,
  ];
  // The next step of the visit, once it has been saved.
  const actions = (
    <View style={{ gap: 8 }}>
      {a.status === 'pending' && (
        <Button mode="contained" icon="check-circle-outline" onPress={() => void status.change(a, 'confirmed', 'Appointment confirmed')}>
          Confirm appointment
        </Button>
      )}
      {(a.status === 'confirmed' || a.status === 'arrived') && (
        <Button mode="contained" icon="play-arrow" onPress={() => void status.change(a, 'in_consultation', 'Consultation started')}>
          Start consultation
        </Button>
      )}
      {(a.status === 'arrived' || a.status === 'in_consultation') && (
        <Button
          mode="contained"
          icon="task-alt"
          onPress={async () => {
            const saved = await completeVisit(a);
            if (saved != null) nav.back('/schedule');
          }}
        >
          Mark done
        </Button>
      )}
      {a.status === 'completed' && (
        <Button mode="outlined" icon="checklist" onPress={() => void completeVisit(a)}>
          Services done
        </Button>
      )}
    </View>
  );

  return (
    <SplitColumns
      startFlex={2}
      endFlex={3}
      // A phone reads top to bottom; a wide screen keeps the visit and its
      // next step on the left, the record beside them.
      narrow={
        <>
          {header}
          {patientCard}
          {clinical.slice(0, 2)}
          {chart}
          {clinical.slice(2)}
          <View style={{ height: 12 }} />
          {actions}
        </>
      }
      // The next step right under the header, above the fold on a tablet
      // held sideways.
      start={
        <>
          {header}
          {actions}
          <View style={{ height: 16 }} />
          {patientCard}
        </>
      }
      end={<>{clinical}</>}
      below={chart}
    />
  );
}
