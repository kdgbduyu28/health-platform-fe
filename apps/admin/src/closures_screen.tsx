import {
  AppCard,
  type Appointment,
  AsyncView,
  BarAction,
  ContentWidth,
  DateField,
  Icon,
  ListTile,
  Page,
  SelectField,
  TextField,
  type TimeOff,
  addDays,
  describeError,
  holdsTime,
  invalidateCatalog,
  isOpenStatus,
  isSameDay,
  startOfDay,
  useAppTheme,
  useClinicAppointments,
  useCurrentClinicId,
  useOverlay,
  useRepository,
  useRoster,
  useTimeOff,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

import { EditorDialog } from './roster_widgets';

/// `Mon, Dec 22` or `Mon, Dec 22 – Fri, Jan 2`.
export function formatDayRange(start: Date, end: Date): string {
  const f = (d: Date) => format(d, 'EEE, MMM d');
  return isSameDay(start, end) ? f(start) : `${f(start)} – ${f(end)}`;
}

/// `/:clinic/settings/closures` — days nobody can book: holidays, when the
/// whole clinic is closed, and a doctor's leave.
///
/// These only stop NEW bookings (`available_slots` offers nothing on those
/// days). Visits already booked are left alone on purpose — the clinic
/// should call those patients, not have their visits vanish — so adding
/// time off says how many there are.
export function ClosuresScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const timeOff = useTimeOff();
  const roster = useRoster().value ?? [];
  const who = (t: TimeOff) => {
    if (t.isClosure) return 'Whole clinic closed';
    const d = roster.find((d) => d.id === t.doctorId);
    return d == null ? 'A doctor' : `Dr. ${d.name}`;
  };

  const add = async () => {
    const saved = await overlay.showDialog<boolean>((close) => <TimeOffEditor close={close} />, { dismissible: false });
    if (saved) invalidateCatalog(qc);
  };

  const remove = async (t: TimeOff) => {
    const ok = await overlay.confirm({
      title: 'Remove this?',
      message: `${who(t)}, ${formatDayRange(t.startsOn, t.endsOn)}. Patients will be able to book those days again.`,
      cancelLabel: 'Keep',
      confirmLabel: 'Remove',
    });
    if (!ok) return;
    try {
      await repo.deleteTimeOff(t.id);
      invalidateCatalog(qc);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <Page title="Closures & leave" back="/settings" maxWidth={ContentWidth.list} fab={{ icon: 'event-busy', label: 'Add', onPress: () => void add() }}>
      <AsyncView value={timeOff} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['timeOff'] })}>
        {(entries) =>
          entries.length === 0 ? (
            <Text style={{ padding: 32, textAlign: 'center' }}>
              No closures or leave coming up. Add holidays and doctors' days off so patients cannot book them.
            </Text>
          ) : (
            <View style={{ gap: 8 }}>
              {entries.map((t) => (
                <AppCard key={t.id}>
                  <ListTile
                    leading={<Icon name={t.isClosure ? 'store-mall-directory' : 'beach-access'} color={t.isClosure ? colors.error : colors.primary} />}
                    title={<Text style={{ fontWeight: '600' }}>{who(t)}</Text>}
                    subtitle={[formatDayRange(t.startsOn, t.endsOn), ...(t.reason != null ? [t.reason] : [])].join(' · ')}
                    trailing={<BarAction icon="delete-outline" label="Remove" onPress={() => void remove(t)} />}
                  />
                </AppCard>
              ))}
            </View>
          )
        }
      </AsyncView>
    </Page>
  );
}

/// Visits still on the calendar from [from] to [to], for whoever is off
/// (everyone, when [doctorId] is null).
function affectedVisits(visits: readonly Appointment[], doctorId: string | null, from: Date, to: Date): number {
  const last = addDays(startOfDay(to), 1).getTime();
  const first = startOfDay(from).getTime();
  return visits.filter(
    (a) =>
      holdsTime(a.status) &&
      isOpenStatus(a.status) &&
      (doctorId == null || a.doctor.id === doctorId) &&
      a.dateTime.getTime() >= first &&
      a.dateTime.getTime() < last,
  ).length;
}

const wholeClinic = '';

function TimeOffEditor({ close }: { close: (saved?: boolean) => void }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const doctors = (useRoster().value ?? []).filter((d) => d.isActive);
  const visits = useClinicAppointments().value ?? [];
  const today = startOfDay(new Date());
  /// Empty: the whole clinic.
  const [doctorId, setDoctorId] = useState(wholeClinic);
  const [from, setFrom] = useState<Date | null>(null);
  const [to, setTo] = useState<Date | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const end = to ?? from;
  const affected = from == null || end == null ? 0 : affectedVisits(visits, doctorId === wholeClinic ? null : doctorId, from, end);

  const save = async () => {
    if (busy) return;
    if (from == null || end == null) {
      setError('Pick the days.');
      return;
    }
    if (end.getTime() < from.getTime()) {
      setError('The last day comes before the first.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await repo.addTimeOff({ clinicId: clinicId!, doctorId: doctorId === wholeClinic ? null : doctorId, startsOn: from, endsOn: end, reason });
      close(true);
    } catch (e) {
      setError(describeError(e));
      setBusy(false);
    }
  };

  return (
    <EditorDialog title="Add closure or leave" width={420} saveLabel="Add" busy={busy} onCancel={() => close(false)} onSave={() => void save()}>
      <SelectField
        label="Who is off"
        value={doctorId}
        options={[{ value: wholeClinic, label: 'Whole clinic (closed)' }, ...doctors.map((d) => ({ value: d.id, label: `Dr. ${d.name}` }))]}
        onChange={setDoctorId}
      />
      <View style={{ flexDirection: 'row', gap: 8, marginTop: 12 }}>
        <DateField
          style={{ flex: 1 }}
          label="First day"
          value={from}
          min={today}
          max={addDays(today, 365)}
          onChange={(d) => {
            setFrom(d);
            if (d != null && to != null && to.getTime() < d.getTime()) setTo(d);
          }}
        />
        <DateField style={{ flex: 1 }} label="Last day" value={to} min={from ?? today} max={addDays(today, 365)} helperText={to == null ? 'Blank: one day' : undefined} onChange={setTo} />
      </View>
      <TextField
        style={{ marginTop: 12 }}
        label="Reason (optional)"
        placeholder="Holiday, conference, leave…"
        autoCapitalize="sentences"
        value={reason}
        onChangeText={setReason}
      />
      {affected > 0 && (
        <View style={{ marginTop: 12, padding: 12, borderRadius: 12, backgroundColor: colors.errorContainer }}>
          <Text style={{ color: colors.onErrorContainer }}>
            {affected} booked {affected === 1 ? 'visit falls' : 'visits fall'} on these days. {affected === 1 ? 'It stays' : 'They stay'} booked — call{' '}
            {affected === 1 ? 'that patient' : 'those patients'} to rebook or cancel.
          </Text>
        </View>
      )}
      {error != null && <Text style={{ marginTop: 12, color: colors.error }}>{error}</Text>}
    </EditorDialog>
  );
}
