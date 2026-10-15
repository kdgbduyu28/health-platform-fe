import {
  AppCard,
  AsyncView,
  ContentWidth,
  type Doctor,
  DoctorAvatar,
  Icon,
  ListTile,
  type Service,
  Wrap,
  addDays,
  describeError,
  isoWeekday,
  startOfDay,
  useAppTheme,
  useAppointmentActions,
  useAvailableSlots,
  useClinicNav,
  useCurrentClinicId,
  useDatePicker,
  useDoctors,
  useMyPatient,
  useOverlay,
  useServices,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { Fragment, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { ActivityIndicator, Appbar, Button, Chip, Divider, Text } from 'react-native-paper';

const stepLabels = ['Service', 'Doctor', 'Schedule', 'Confirm'];

export function BookAppointmentScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const actions = useAppointmentActions();
  const clinicId = useCurrentClinicId();
  const patient = useMyPatient().value ?? null;
  const servicesAsync = useServices();
  const doctorsAsync = useDoctors();
  const [step, setStep] = useState(0);
  const [service, setService] = useState<Service | null>(null);
  const [doctor, setDoctor] = useState<Doctor | null>(null);
  const [date, setDate] = useState<Date | null>(null);
  /// A start time `available_slots` offered — not built from the date and a
  /// string, so it is exactly the instant the database will check.
  const [slot, setSlot] = useState<Date | null>(null);
  const [busy, setBusy] = useState(false);

  const confirm = async () => {
    if (service == null || doctor == null || slot == null) return;
    if (clinicId == null) {
      overlay.snack('Still loading the clinic. Try again in a moment.');
      return;
    }
    // The app only opens once this account holds a chart at the current
    // clinic, so this guards a stale session rather than a normal path —
    // without a chart there is no patient_id to book against.
    if (patient == null) {
      overlay.snack("You have not joined this clinic yet. Join it from your profile with the clinic's code.");
      return;
    }
    setBusy(true);
    try {
      await actions.book({ clinicId, patientId: patient.id, doctorId: doctor.id, serviceId: service.id, serviceName: service.name, scheduledAt: slot });
      overlay.snack('Appointment requested. The clinic will confirm it.');
      nav.go('/appointments');
    } catch (e) {
      // Most likely someone took the time first. Back to the list, which
      // is refetched without it.
      void qc.invalidateQueries({ queryKey: ['slots'] });
      setSlot(null);
      setStep(2);
      overlay.snack(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.surface }}>
      <Appbar.Header statusBarHeight={0} mode="small" style={{ backgroundColor: colors.surface }}>
        <Appbar.BackAction onPress={() => (step === 0 ? nav.back('/home') : setStep(step - 1))} />
        <Appbar.Content title="Book Appointment" />
      </Appbar.Header>
      <StepIndicator step={step} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16 }}>
        <View style={{ width: '100%', maxWidth: ContentWidth.form, alignSelf: 'center' }}>
          {step === 0 ? (
            <AsyncView value={servicesAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['services'] })}>
              {(services) => (
                <ServiceStep
                  services={services}
                  selected={service}
                  onSelect={(s) => {
                    setService(s);
                    setStep(1);
                  }}
                />
              )}
            </AsyncView>
          ) : step === 1 ? (
            <AsyncView value={doctorsAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['doctors'] })}>
              {(doctors) => (
                <DoctorStep
                  doctors={doctors}
                  selected={doctor}
                  onSelect={(d) => {
                    setDoctor(d);
                    setStep(2);
                  }}
                />
              )}
            </AsyncView>
          ) : step === 2 ? (
            <DateTimeStep
              doctor={doctor}
              service={service}
              selectedDate={date}
              selectedSlot={slot}
              onDateSelected={(d) => {
                setDate(d);
                setSlot(null);
              }}
              onSlotSelected={(s) => {
                setSlot(s);
                setStep(3);
              }}
            />
          ) : (
            <ConfirmStep service={service} doctor={doctor} slot={slot} busy={busy} onConfirm={() => void confirm()} />
          )}
        </View>
      </ScrollView>
    </View>
  );
}

function StepIndicator({ step }: { step: number }) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        flexDirection: 'row',
        paddingHorizontal: 16,
        paddingVertical: 12,
        backgroundColor: colors.surface,
        borderBottomWidth: 1,
        borderBottomColor: colors.outlineVariant,
      }}
    >
      {stepLabels.map((label, i) => {
        const active = i === step;
        const done = i < step;
        return (
          <View key={label} style={{ flex: 1, flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <View
              style={{
                width: 28,
                height: 28,
                borderRadius: 14,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: done || active ? colors.primary : colors.surfaceContainerHighest,
              }}
            >
              {done ? (
                <Icon name="check" size={14} color={colors.onPrimary} />
              ) : (
                <Text style={{ fontSize: 12, fontWeight: '700', color: active ? colors.onPrimary : colors.outline }}>{i + 1}</Text>
              )}
            </View>
            <Text
              numberOfLines={1}
              style={{ flexShrink: 1, fontSize: 11, fontWeight: active ? '700' : '400', color: active ? colors.primary : colors.outline }}
            >
              {label}
            </Text>
            {i < stepLabels.length - 1 && <View style={{ flex: 1, height: 1, marginHorizontal: 4, backgroundColor: colors.outlineVariant }} />}
          </View>
        );
      })}
    </View>
  );
}

function StepTitle({ children }: { children: string }) {
  return (
    <Text variant="titleLarge" style={{ fontWeight: '700', marginBottom: 16 }}>
      {children}
    </Text>
  );
}

function ServiceStep({ services, selected, onSelect }: { services: Service[]; selected: Service | null; onSelect: (s: Service) => void }) {
  const { colors } = useAppTheme();
  if (services.length === 0) {
    return <Text style={{ padding: 32, textAlign: 'center' }}>This clinic has no bookable services.</Text>;
  }
  return (
    <View>
      <StepTitle>Select a service</StepTitle>
      <Wrap align="flex-start">
        {services.map((s) => {
          const on = s.id === selected?.id;
          return (
            <Chip
              key={s.id}
              mode="outlined"
              selected={on}
              showSelectedCheck
              onPress={() => onSelect(s)}
              style={on ? { backgroundColor: colors.primaryContainer } : undefined}
            >
              {[s.name, `${s.durationMinutes} min`, ...(s.priceLabel != null ? [s.priceLabel] : [])].join(' · ')}
            </Chip>
          );
        })}
      </Wrap>
    </View>
  );
}

function DoctorStep({ doctors, selected, onSelect }: { doctors: Doctor[]; selected: Doctor | null; onSelect: (d: Doctor) => void }) {
  const { colors } = useAppTheme();
  if (doctors.length === 0) {
    return <Text style={{ padding: 32, textAlign: 'center' }}>No doctors are available right now.</Text>;
  }
  return (
    <View>
      <StepTitle>Choose a doctor</StepTitle>
      <View style={{ gap: 8 }}>
        {doctors.map((d) => {
          const on = d.id === selected?.id;
          return (
            <AppCard key={d.id} style={{ borderColor: on ? colors.primary : colors.outlineVariant, borderWidth: on ? 2 : 1 }}>
              <ListTile
                onPress={() => onSelect(d)}
                leading={<DoctorAvatar doctor={d} />}
                title={<Text style={{ fontWeight: '600' }}>Dr. {d.name}</Text>}
                subtitle={d.specialty}
                trailing={on ? <Icon name="check-circle" color={colors.primary} /> : undefined}
              />
            </AppCard>
          );
        })}
      </View>
    </View>
  );
}

/// The date picker should open on a day the doctor works.
function firstWorkingDay(today: Date, doctor: Doctor | null): Date {
  const days = doctor?.availableWeekdays ?? [];
  for (let i = 1; i <= 7; i++) {
    const day = addDays(today, i);
    if (days.length === 0 || days.includes(isoWeekday(day))) return day;
  }
  return today;
}

function DateTimeStep({
  doctor,
  service,
  selectedDate,
  selectedSlot,
  onDateSelected,
  onSlotSelected,
}: {
  doctor: Doctor | null;
  service: Service | null;
  selectedDate: Date | null;
  selectedSlot: Date | null;
  onDateSelected: (d: Date) => void;
  onSlotSelected: (s: Date) => void;
}) {
  const pickDate = useDatePicker();
  const date = selectedDate;
  return (
    <View>
      <StepTitle>Pick a date & time</StepTitle>
      <Button
        mode="outlined"
        icon="calendar-today"
        contentStyle={{ height: 52 }}
        style={{ borderRadius: 12 }}
        onPress={async () => {
          const today = startOfDay(new Date());
          const picked = await pickDate({
            initial: firstWorkingDay(today, doctor),
            first: today,
            last: addDays(today, 60),
            selectable: (day) => doctor?.availableWeekdays.includes(isoWeekday(day)) ?? true,
          });
          if (picked) onDateSelected(picked);
        }}
      >
        {date == null ? 'Select date' : format(date, 'EEEE, MMMM d, y')}
      </Button>
      {date != null && doctor != null && <Slots doctor={doctor} service={service} date={date} selected={selectedSlot} onSelect={onSlotSelected} />}
    </View>
  );
}

function Slots({
  doctor,
  service,
  date,
  selected,
  onSelect,
}: {
  doctor: Doctor;
  service: Service | null;
  date: Date;
  selected: Date | null;
  onSelect: (s: Date) => void;
}) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const slots = useAvailableSlots({ doctorId: doctor.id, day: date, serviceId: service?.id ?? null, ignore: null });
  return (
    <View>
      <Text variant="titleMedium" style={{ marginTop: 20, marginBottom: 12 }}>
        Available times
      </Text>
      <AsyncView value={slots} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['slots'] })}>
        {(slots) =>
          slots.length === 0 ? (
            <Text style={{ color: colors.onSurfaceVariant }}>
              No times left on this day. Dr. {doctor.name} may be fully booked or away — try another date.
            </Text>
          ) : (
            <Wrap align="flex-start">
              {slots.map((s) => {
                const on = s.getTime() === selected?.getTime();
                return (
                  <Chip
                    key={s.getTime()}
                    mode="outlined"
                    selected={on}
                    onPress={() => onSelect(s)}
                    style={on ? { backgroundColor: colors.primaryContainer } : undefined}
                  >
                    {format(s, 'h:mm a')}
                  </Chip>
                );
              })}
            </Wrap>
          )
        }
      </AsyncView>
    </View>
  );
}

function ConfirmStep({
  service,
  doctor,
  slot,
  busy,
  onConfirm,
}: {
  service: Service | null;
  doctor: Doctor | null;
  slot: Date | null;
  busy: boolean;
  onConfirm: () => void;
}) {
  const { colors } = useAppTheme();
  const rows: [string, string][] = [
    ['Service', service?.name ?? ''],
    ...(service?.priceLabel != null ? [['Price', service.priceLabel] as [string, string]] : []),
    ['Doctor', `Dr. ${doctor?.name ?? ''}`],
    ['Specialty', doctor?.specialty ?? ''],
    ['Date', slot != null ? format(slot, 'EEEE, MMMM d, y') : ''],
    ['Time', slot != null ? `${format(slot, 'h:mm a')} · ${service?.durationMinutes ?? 30} min` : ''],
  ];
  return (
    <View>
      <StepTitle>Confirm appointment</StepTitle>
      <View style={{ padding: 20, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
        {rows.map(([label, value], i) => (
          <Fragment key={label}>
            {i > 0 && <Divider style={{ marginVertical: 12 }} />}
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: 12 }}>
              <Text style={{ color: colors.onSurfaceVariant }}>{label}</Text>
              <Text style={{ fontWeight: '600', flexShrink: 1, textAlign: 'right' }}>{value}</Text>
            </View>
          </Fragment>
        ))}
      </View>
      <Button mode="contained" disabled={busy} onPress={onConfirm} style={{ marginTop: 24 }} contentStyle={{ height: 48 }}>
        {busy ? <ActivityIndicator size={20} /> : 'Confirm Booking'}
      </Button>
    </View>
  );
}
