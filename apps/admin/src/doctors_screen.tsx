import {
  AppCard,
  AsyncView,
  ContentWidth,
  type Doctor,
  DoctorAvatar,
  Icon,
  ListTile,
  Page,
  SelectField,
  TextField,
  type WorkingHours,
  Wrap,
  describeError,
  describeTimeSlots,
  formatClock,
  formatWeekdays,
  generateTimeSlots,
  invalidateCatalog,
  parseClock,
  useAppTheme,
  useCurrentClinicId,
  useOverlay,
  useRepository,
  useRoster,
  useTimePicker,
  workingHoursOf,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Chip, Text } from 'react-native-paper';

import { EditorDialog, SwitchRow, Tag } from './roster_widgets';

/// `/:clinic/settings/doctors` — the roster, and each doctor's working week.
///
/// What a doctor can be booked for comes from here: their weekdays and the
/// start times on each (see `public.available_slots`). Doctors are
/// deactivated rather than removed; their past visits still point at them.
export function DoctorsScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const roster = useRoster();

  const edit = async (doctor: Doctor | null) => {
    const saved = await overlay.showDialog<boolean>((close) => <DoctorEditor doctor={doctor} close={close} />, { dismissible: false });
    if (saved) invalidateCatalog(qc);
  };

  return (
    <Page title="Doctors" back="/settings" maxWidth={ContentWidth.list} fab={{ icon: 'person-add-alt-1', label: 'Add doctor', onPress: () => void edit(null) }}>
      <AsyncView value={roster} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['roster'] })}>
        {(doctors) =>
          doctors.length === 0 ? (
            <Text style={{ padding: 32, textAlign: 'center' }}>No doctors yet. Add one so patients have someone to book.</Text>
          ) : (
            <View style={{ gap: 8 }}>
              {doctors.map((d) => (
                <AppCard key={d.id}>
                  <ListTile
                    onPress={() => void edit(d)}
                    leading={<DoctorAvatar doctor={d} />}
                    title={<Text style={{ fontWeight: '600', color: d.isActive ? undefined : colors.outline }}>Dr. {d.name}</Text>}
                    subtitle={[
                      ...(d.specialty !== '' ? [d.specialty] : []),
                      d.availableWeekdays.length === 0 ? 'No working days' : formatWeekdays(d.availableWeekdays),
                      describeTimeSlots(d.availableTimeSlots),
                    ].join('\n')}
                    trailing={d.isActive ? <Icon name="edit" /> : <Tag label="Inactive" />}
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

const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const steps = [10, 15, 20, 30, 45, 60];

function DoctorEditor({ doctor, close }: { doctor: Doctor | null; close: (saved?: boolean) => void }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const pickTime = useTimePicker();
  const isNew = doctor == null;
  const [name, setName] = useState(doctor?.name ?? '');
  const [specialty, setSpecialty] = useState(doctor?.specialty ?? '');
  const [weekdays, setWeekdays] = useState<Set<number>>(() => new Set(doctor == null ? [1, 2, 3, 4, 5] : doctor.availableWeekdays));
  const [active, setActive] = useState(doctor?.isActive ?? true);
  const [fieldErrors, setFieldErrors] = useState<{ name?: string; specialty?: string }>({});

  /// The hours as first time / last time / every N minutes. Starts from the
  /// doctor's current times when they fit that shape.
  const slots0 = doctor?.availableTimeSlots ?? [];
  const pattern = workingHoursOf(slots0);
  const [hours, setHours] = useState<WorkingHours>(pattern ?? { first: 9 * 60, last: 16 * 60 + 30, step: 30 });
  /// The doctor's current times do not fit a first/last/step pattern (a
  /// lunch break, say). They are kept unless the admin edits the hours.
  const [keepIrregular, setKeepIrregular] = useState(slots0.length > 0 && pattern == null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const slots = keepIrregular ? slots0 : generateTimeSlots(hours);

  const pick = async (first: boolean) => {
    const current = first ? hours.first : hours.last;
    const picked = await pickTime({ initial: formatClock(current) });
    const m = picked == null ? null : parseClock(picked);
    if (m == null) return;
    setKeepIrregular(false);
    setHours(
      first
        ? { first: m, last: hours.last < m ? m : hours.last, step: hours.step }
        : { first: hours.first > m ? m : hours.first, last: m, step: hours.step },
    );
  };

  const save = async () => {
    if (busy) return;
    const errs = {
      name: name.trim() === '' ? 'Enter a name' : undefined,
      specialty: specialty.trim() === '' ? 'Enter a specialty' : undefined,
    };
    setFieldErrors(errs);
    if (errs.name != null || errs.specialty != null) return;
    if (weekdays.size === 0 && active) {
      setError('Pick at least one working day.');
      return;
    }
    if (slots.length === 0 && active) {
      setError('Set at least one start time.');
      return;
    }
    setBusy(true);
    setError(null);
    const days = [...weekdays].sort((a, b) => a - b);
    try {
      if (doctor == null) {
        await repo.addDoctor({ clinicId: clinicId!, name: name.trim(), specialty: specialty.trim(), weekdays: days, timeSlots: slots });
      } else {
        await repo.updateDoctor(doctor.id, {
          full_name: name.trim(),
          specialty: specialty.trim(),
          available_weekdays: days,
          available_time_slots: slots,
          is_active: active,
        });
      }
      close(true);
    } catch (e) {
      setError(describeError(e));
      setBusy(false);
    }
  };

  return (
    <EditorDialog
      title={isNew ? 'Add doctor' : `Edit Dr. ${doctor.name}`}
      saveLabel={isNew ? 'Add' : 'Save'}
      busy={busy}
      onCancel={() => close(false)}
      onSave={() => void save()}
    >
      <TextField label="Full name" placeholder='Maria Santos (no "Dr.")' value={name} onChangeText={setName} autoFocus={isNew} autoCapitalize="words" error={fieldErrors.name} />
      <View style={{ height: 12 }} />
      <TextField label="Specialty" value={specialty} onChangeText={setSpecialty} autoCapitalize="words" error={fieldErrors.specialty} />
      <Text variant="titleSmall" style={{ marginTop: 20, marginBottom: 8 }}>
        Working days
      </Text>
      <Wrap spacing={6} runSpacing={6} align="flex-start">
        {dayNames.map((label, i) => {
          const d = i + 1;
          const on = weekdays.has(d);
          return (
            <Chip
              key={d}
              mode="outlined"
              selected={on}
              showSelectedCheck
              onPress={() => {
                const next = new Set(weekdays);
                if (on) next.delete(d);
                else next.add(d);
                setWeekdays(next);
              }}
            >
              {label}
            </Chip>
          );
        })}
      </Wrap>
      <Text variant="titleSmall" style={{ marginTop: 20, marginBottom: 8 }}>
        Hours
      </Text>
      {keepIrregular && (
        <Text style={{ color: colors.onSurfaceVariant, fontSize: 13, marginBottom: 8 }}>
          Keeps the current {slots0.length} start times ({slots0.join(', ')}). Change the hours below to replace them with an even schedule.
        </Text>
      )}
      <View style={{ flexDirection: 'row', gap: 8 }}>
        <Button mode="outlined" style={{ flex: 1 }} onPress={() => void pick(true)}>
          First {formatClock(hours.first)}
        </Button>
        <Button mode="outlined" style={{ flex: 1 }} onPress={() => void pick(false)}>
          Last {formatClock(hours.last)}
        </Button>
      </View>
      <SelectField
        style={{ marginTop: 8 }}
        label="Every"
        value={steps.includes(hours.step) ? hours.step : 30}
        options={steps.map((m) => ({ value: m, label: `${m} minutes` }))}
        onChange={(m) => {
          setKeepIrregular(false);
          setHours({ ...hours, step: m });
        }}
      />
      <Text style={{ marginTop: 8, color: colors.onSurfaceVariant, fontSize: 12 }}>
        {slots.length} start times a day. The last start time is the latest a visit can begin; longer services only fit where the doctor is free for
        their whole length.
      </Text>
      {!isNew && (
        <View style={{ marginTop: 12 }}>
          <SwitchRow
            title="Taking bookings"
            subtitle="Off hides this doctor from booking. Visits already booked stay booked."
            value={active}
            onChange={setActive}
          />
        </View>
      )}
      {error != null && <Text style={{ marginTop: 12, color: colors.error }}>{error}</Text>}
    </EditorDialog>
  );
}
