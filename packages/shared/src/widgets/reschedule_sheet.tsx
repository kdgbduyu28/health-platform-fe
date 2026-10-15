import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Chip, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import type { Doctor } from '../models/doctor';
import { useAppointmentActions } from '../queries/appointments';
import { useAvailableSlots, useDoctors } from '../queries/catalog';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { SelectField, useDatePicker, useTimePicker } from '../ui/fields';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { addDays, isoWeekday, startOfDay } from '../util/dates';
import { visitTimeFormat } from './appointment_bits';

/// Moves an appointment to a new time, and says how it went. Answers whether
/// it moved.
///
/// A patient picks from the times the clinic offers, and learns the clinic
/// must confirm again. Staff may also switch the doctor, or set a time off
/// the grid — the database still refuses an overlap.
export function useRescheduleSheet(): (appointment: Appointment, staff: boolean) => Promise<boolean> {
  const overlay = useOverlay();
  return async (appointment, staff) => {
    const moved = await overlay.showSheet<Date>((close) => <RescheduleSheet appointment={appointment} staff={staff} close={close} />);
    if (moved == null) return false;
    const when = format(moved, visitTimeFormat);
    overlay.snack(staff ? `Moved to ${when}` : `Moved to ${when}. The clinic will confirm the new time.`);
    return true;
  };
}

function RescheduleSheet({ appointment: a, staff, close }: { appointment: Appointment; staff: boolean; close: Close<Date> }) {
  const { colors } = useAppTheme();
  const actions = useAppointmentActions();
  const qc = useQueryClient();
  const doctors = useDoctors();
  const pickDate = useDatePicker();
  const pickTime = useTimePicker();
  const [doctor, setDoctor] = useState<Doctor>(a.doctor);
  const [day, setDay] = useState<Date | null>(null);
  const [slot, setSlot] = useState<Date | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const slots = useAvailableSlots(day == null ? null : { doctorId: doctor.id, day, serviceId: a.serviceId, ignore: a.id });

  const pickDay = async () => {
    const today = startOfDay(new Date());
    const weekdays = doctor.availableWeekdays;
    // Staff may book any day; a patient only the doctor's working days.
    const selectable = (d: Date) => staff || weekdays.length === 0 || weekdays.includes(isoWeekday(d));
    let initial = day ?? today;
    for (let i = 0; i < 14 && !selectable(initial); i++) initial = addDays(initial, 1);
    const picked = await pickDate({
      initial: selectable(initial) ? initial : today,
      first: today,
      last: addDays(today, 90),
      selectable,
    });
    if (picked) {
      setDay(picked);
      setSlot(null);
      setError(null);
    }
  };

  const pickOffGridTime = async (d: Date) => {
    const base = slot ?? a.dateTime;
    const t = await pickTime({ initial: format(base, 'HH:mm') });
    if (t == null) return;
    const [h, m] = t.split(':').map(Number);
    setSlot(new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m));
    setError(null);
  };

  const save = async () => {
    if (slot == null) return;
    setBusy(true);
    setError(null);
    try {
      await actions.reschedule(a.id, slot, doctor.id === a.doctor.id ? null : doctor.id);
      void qc.invalidateQueries({ queryKey: ['slots'] });
      close(slot);
    } catch (e) {
      // Most likely someone took the time first; the list refetches without it.
      void qc.invalidateQueries({ queryKey: ['slots'] });
      setError(describeError(e));
      setSlot(null);
    } finally {
      setBusy(false);
    }
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        Move this visit
      </Text>
      <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        {a.service} · now {format(a.dateTime, visitTimeFormat)}
      </Text>
      {!staff && a.status === 'confirmed' && (
        <Text style={{ marginTop: 8, color: colors.onSurfaceVariant, fontSize: 13 }}>
          Your visit is confirmed. A new time goes back to the clinic to confirm.
        </Text>
      )}
      {staff && (
        <View style={{ marginTop: 16 }}>
          <AsyncView value={doctors} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['doctors'] })}>
            {(list) => {
              const options = [a.doctor, ...list.filter((d) => d.id !== a.doctor.id)];
              return (
                <SelectField
                  label="Doctor"
                  value={doctor.id}
                  options={options.map((d) => ({ value: d.id, label: `Dr. ${d.name}` }))}
                  onChange={(id) => {
                    setDoctor(options.find((d) => d.id === id) ?? a.doctor);
                    setSlot(null);
                  }}
                />
              );
            }}
          </AsyncView>
        </View>
      )}
      <Button mode="outlined" icon="calendar-today" onPress={pickDay} style={{ marginTop: 16 }} contentStyle={{ height: 52 }}>
        {day == null ? 'Pick a day' : format(day, 'EEEE, MMMM d, y')}
      </Button>
      {day != null && (
        <View style={{ marginTop: 16 }}>
          <AsyncView value={slots} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['slots'] })}>
            {(list) => (
              <View>
                {list.length === 0 ? (
                  <Text style={{ color: colors.onSurfaceVariant }}>
                    No times left on this day. Dr. {doctor.name} may be fully booked or away — try another day.
                  </Text>
                ) : (
                  <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
                    {list.map((s) => (
                      <Chip key={s.getTime()} mode="outlined" selected={slot?.getTime() === s.getTime()} showSelectedCheck onPress={() => setSlot(s)}>
                        {format(s, 'h:mm a')}
                      </Chip>
                    ))}
                  </View>
                )}
                {staff && (
                  <Button icon="more-time" onPress={() => pickOffGridTime(day)} style={{ alignSelf: 'flex-start', marginTop: 8 }}>
                    {slot != null && !list.some((s) => s.getTime() === slot.getTime()) ? `Other time: ${format(slot, 'h:mm a')}` : 'Other time…'}
                  </Button>
                )}
              </View>
            )}
          </AsyncView>
        </View>
      )}
      {error != null && <Text style={{ marginTop: 12, color: colors.error }}>{error}</Text>}
      <Button mode="contained" disabled={slot == null || busy} onPress={save} style={{ marginTop: 20 }} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : slot == null ? 'Pick a new time' : `Move to ${format(slot, visitTimeFormat)}`}
      </Button>
    </SheetScroll>
  );
}
