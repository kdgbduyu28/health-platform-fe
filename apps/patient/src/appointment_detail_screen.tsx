import {
  AddToCalendarButton,
  type Appointment,
  AsyncView,
  ContentWidth,
  DoctorAvatar,
  GradientBox,
  Icon,
  type IconName,
  Page,
  StatusBadge,
  VisitBillSection,
  VisitDentalSummary,
  describeError,
  patientCanCancel,
  refreshAppointments,
  useAppTheme,
  useAppointmentActions,
  useAppointmentById,
  useClinicById,
  useClinicNav,
  useOverlay,
  useRescheduleSheet,
  withAlpha,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import type { ReactNode } from 'react';
import { View } from 'react-native';
import { Button, Text } from 'react-native-paper';

export function AppointmentDetailScreen({ appointmentId }: { appointmentId: string }) {
  const qc = useQueryClient();
  const async = useAppointmentById(appointmentId);
  return (
    <Page title="Appointment Details" back="/appointments" maxWidth={ContentWidth.list}>
      <AsyncView value={async} padded onRetry={() => void refreshAppointments(qc)}>
        {(a) => (a == null ? <Text style={{ textAlign: 'center', padding: 32 }}>Appointment not found.</Text> : <Details appointment={a} />)}
      </AsyncView>
    </Page>
  );
}

function Details({ appointment: a }: { appointment: Appointment }) {
  const { colors } = useAppTheme();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const actions = useAppointmentActions();
  const reschedule = useRescheduleSheet();
  const clinic = useClinicById(a.clinicId);
  const on = colors.onPrimary;

  const cancel = async () => {
    const ok = await overlay.confirm({
      title: 'Cancel Appointment',
      message: 'Are you sure you want to cancel this appointment?',
      cancelLabel: 'Keep',
      confirmLabel: 'Cancel Appointment',
      destructive: true,
    });
    if (!ok) return;
    try {
      await actions.updateStatus(a.id, 'cancelled');
      nav.back('/appointments');
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <View style={{ gap: 12 }}>
      <GradientBox style={{ padding: 20, marginBottom: 4 }}>
        <View style={{ alignSelf: 'flex-start', backgroundColor: colors.surface, borderRadius: 20 }}>
          <StatusBadge status={a.status} />
        </View>
        <Text variant="headlineSmall" style={{ marginTop: 12, color: on, fontWeight: '700' }}>
          {a.service}
        </Text>
        <Text style={{ marginTop: 4, color: withAlpha(on, 200 / 255), fontSize: 13 }}>{clinic?.name ?? ''}</Text>
      </GradientBox>

      <InfoCard>
        <InfoTile icon="calendar-today" label="Date" value={format(a.dateTime, 'EEEE, MMMM d, y')} />
        <InfoTile icon="access-time" label="Time" value={format(a.dateTime, 'h:mm a')} />
        {a.rescheduledFrom != null && <InfoTile icon="update" label="Moved from" value={format(a.rescheduledFrom, 'EEE, MMM d · h:mm a')} />}
      </InfoCard>

      <InfoCard>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <DoctorAvatar doctor={a.doctor} radius={28} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontWeight: '600', fontSize: 16 }}>Dr. {a.doctor.name}</Text>
            <Text style={{ color: colors.onSurfaceVariant }}>{a.doctor.specialty}</Text>
          </View>
        </View>
      </InfoCard>

      {/* What the doctor left for the patient. The clinic's clinical notes
          are not readable from a patient account at all. */}
      {a.patientNote != null && (
        <InfoCard>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
            <Icon name="chat-bubble-outline" size={16} color={colors.primary} />
            <Text style={{ fontWeight: '600', color: colors.onSurfaceVariant }}>Note from your doctor</Text>
          </View>
          <Text style={{ marginTop: 6 }}>{a.patientNote}</Text>
        </InfoCard>
      )}

      {/* At a dental clinic: which teeth were treated, what was found, what
          comes next — in plain words, without the clinic's notes. */}
      <VisitDentalSummary patientId={a.patient.id} appointmentId={a.id} forPatient />

      <VisitBillSection appointment={a} onOpenInvoice={(id) => nav.push(`/bills/${id}`)} />

      {a.canReschedule && a.isUpcoming && <AddToCalendarButton appointment={a} />}
      {a.canReschedule && (
        <Button mode="contained-tonal" icon="edit-calendar" onPress={() => void reschedule(a, false)}>
          Reschedule
        </Button>
      )}
      {patientCanCancel(a.status) && (
        <Button mode="outlined" icon="cancel" textColor={colors.error} style={{ borderColor: colors.error }} onPress={() => void cancel()}>
          Cancel Appointment
        </Button>
      )}
    </View>
  );
}

function InfoCard({ children }: { children: ReactNode }) {
  const { colors } = useAppTheme();
  return <View style={{ padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>{children}</View>;
}

function InfoTile({ icon, label, value }: { icon: IconName; label: string; value: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 }}>
      <Icon name={icon} size={18} color={colors.primary} />
      <View>
        <Text style={{ fontSize: 11, color: colors.onSurfaceVariant }}>{label}</Text>
        <Text style={{ fontWeight: '600' }}>{value}</Text>
      </View>
    </View>
  );
}
