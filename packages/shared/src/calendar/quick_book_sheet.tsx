import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import type { Doctor } from '../models/doctor';
import type { Service } from '../models/service';
import { useAppointmentActions, useClinicAppointments } from '../queries/appointments';
import { invalidatePatientLists, useDoctors, useServices, useTimeOff } from '../queries/catalog';
import { useCurrentClinicId } from '../queries/clinic';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { SelectField, useDatePicker, useTimePicker } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { addDays, addMinutes, startOfDay } from '../util/dates';
import { type ChosenPatient, PatientChooser, hasChosenPatient, noPatientChosen } from '../widgets/patient_chooser';
import { checkBooking } from './booking_check';

/// Books a visit from the calendar: the time and doctor come from where the
/// grid was tapped, and can still be changed. Answers whether it booked.
///
/// For a patient on file, or someone new registered with the booking. Staff
/// bookings go in confirmed. Clashes show as they are picked; the database
/// has the last word (a doctor or a patient in two places at once).
export function useQuickBookSheet(): (start: Date, doctor?: Doctor | null) => Promise<boolean> {
  const overlay = useOverlay();
  return async (start, doctor) => {
    const booked = await overlay.showSheet<string>((close) => <QuickBookSheet start={start} doctor={doctor ?? null} close={close} />);
    if (booked == null) return false;
    overlay.snack(booked);
    return true;
  };
}

function QuickBookSheet({ start, doctor: given, close }: { start: Date; doctor: Doctor | null; close: Close<string> }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const actions = useAppointmentActions();
  const clinicId = useCurrentClinicId();
  const doctors = useDoctors().value ?? [];
  const services = useServices().value ?? [];
  const appointments = useClinicAppointments().value ?? [];
  const timeOff = useTimeOff().value ?? [];
  const pickDate = useDatePicker();
  const pickTime = useTimePicker();
  const [chosen, setChosen] = useState<ChosenPatient>(noPatientChosen);
  const [day, setDay] = useState(() => startOfDay(start));
  const [time, setTime] = useState(() => format(start, 'HH:mm'));
  const [doctorId, setDoctorId] = useState<string | null>(given?.id ?? null);
  const [service, setService] = useState<Service | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [hh, mm] = time.split(':').map(Number);
  const when = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hh, mm);
  const doctor = doctors.find((d) => d.id === doctorId) ?? given;
  const patient = chosen.isNew ? null : chosen.patient;
  const check =
    doctor == null
      ? null
      : checkBooking({ start: when, minutes: service?.durationMinutes ?? 30, doctor, appointments, timeOff, patientId: patient?.id, patientName: patient?.name });
  const canSave = hasChosenPatient(chosen) && doctor != null && service != null && (check?.blocking.length ?? 1) === 0 && !busy;

  const save = async () => {
    if (service == null || doctor == null) return;
    if (clinicId == null) {
      setError('Still loading the clinic. Try again in a moment.');
      return;
    }
    const name = patient?.name ?? chosen.newName.trim();
    setBusy(true);
    setError(null);
    try {
      if (patient != null) {
        await actions.book({ clinicId, patientId: patient.id, doctorId: doctor.id, serviceId: service.id, serviceName: service.name, scheduledAt: when, status: 'confirmed' });
      } else {
        // One RPC, one transaction: no orphan chart if the time is lost.
        await actions.bookWalkIn({ clinicId, fullName: name, phone: chosen.newPhone.trim(), doctorId: doctor.id, serviceId: service.id, serviceName: service.name, scheduledAt: when });
        invalidatePatientLists(qc);
      }
      void qc.invalidateQueries({ queryKey: ['slots'] });
      close(`${name} booked with Dr. ${doctor.name}, ${format(when, 'EEE, MMM d · h:mm a')}`);
    } catch (e) {
      // Most likely someone took the time first: the refetch shows the clash.
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        New appointment
      </Text>
      <View style={{ flexDirection: 'row', gap: 8, marginTop: 16 }}>
        <Button
          mode="outlined"
          icon="calendar-today"
          style={{ flex: 1 }}
          contentStyle={{ height: 48 }}
          onPress={async () => {
            const today = startOfDay(new Date());
            const picked = await pickDate({ initial: day.getTime() < today.getTime() ? today : day, first: today, last: addDays(today, 365) });
            if (picked) setDay(picked);
          }}
        >
          {format(day, 'EEE, MMM d')}
        </Button>
        <Button
          mode="outlined"
          icon="schedule"
          style={{ flex: 1 }}
          contentStyle={{ height: 48 }}
          onPress={async () => {
            const picked = await pickTime({ initial: time });
            if (picked) setTime(picked);
          }}
        >
          {format(when, 'h:mm a')}
        </Button>
      </View>
      <SelectField
        style={{ marginTop: 16 }}
        label="Doctor"
        value={doctors.some((d) => d.id === doctorId) ? doctorId : null}
        options={doctors.map((d) => ({ value: d.id, label: `Dr. ${d.name}` }))}
        onChange={setDoctorId}
      />
      <SelectField
        style={{ marginTop: 16 }}
        label="Service"
        value={service?.id ?? null}
        helperText={service == null ? undefined : `Until ${format(addMinutes(when, service.durationMinutes), 'h:mm a')}`}
        options={services.map((s) => ({ value: s.id, label: `${s.name} · ${s.durationMinutes} min` }))}
        onChange={(id) => setService(services.find((s) => s.id === id) ?? null)}
      />
      <View style={{ height: 16 }} />
      <PatientChooser value={chosen} onChange={setChosen} />
      {check?.blocking.map((b) => <NoticeLine key={b} text={b} icon="block" color={colors.error} />)}
      {check?.warnings.map((w) => <NoticeLine key={w} text={w} icon="info-outline" color={colors.tertiary} />)}
      {error != null && <NoticeLine text={error} icon="error-outline" color={colors.error} />}
      <Button mode="contained" disabled={!canSave} onPress={save} style={{ marginTop: 20 }} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : 'Book'}
      </Button>
    </SheetScroll>
  );
}

function NoticeLine({ text, icon, color }: { text: string; icon: IconName; color: string }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 8, marginTop: 10 }}>
      <Icon name={icon} size={18} color={color} />
      <Text style={{ flex: 1, color }}>{text}</Text>
    </View>
  );
}
