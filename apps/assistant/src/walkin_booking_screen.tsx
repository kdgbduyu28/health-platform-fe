import {
  AppCard,
  AsyncView,
  Avatar,
  ContentWidth,
  type Doctor,
  DoctorAvatar,
  Icon,
  ListTile,
  Page,
  type Patient,
  type Service,
  SplitColumns,
  TextField,
  Wrap,
  describeError,
  invalidatePatientLists,
  startOfDay,
  useAppTheme,
  useAppointmentActions,
  useAvailableSlots,
  useClinicNav,
  useCurrentClinicId,
  useDoctors,
  useOverlay,
  usePatientById,
  usePatientSearch,
  useServices,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useEffect, useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Chip, Dialog, ProgressBar, SegmentedButtons, Text } from 'react-native-paper';

type PatientMode = 'existing' | 'new';

export function WalkInBookingScreen({ initialPatientId }: { initialPatientId?: string | null }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const overlay = useOverlay();
  const actions = useAppointmentActions();
  const clinicId = useCurrentClinicId();
  const doctors = useDoctors().value ?? [];
  const services = useServices().value ?? [];

  // Search first. book_walk_in always registers a NEW person and chart, so
  // registering someone already on file splits their history in two.
  const [mode, setMode] = useState<PatientMode>('existing');
  const [patientId, setPatientId] = useState<string | null>(initialPatientId ?? null);
  const [query, setQuery] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [errors, setErrors] = useState<{ name?: string; phone?: string }>({});
  const [service, setService] = useState<Service | null>(null);
  const [doctor, setDoctor] = useState<Doctor | null>(null);
  /// One of today's times `available_slots` offered.
  const [slot, setSlot] = useState<Date | null>(null);
  const [busy, setBusy] = useState(false);

  // Arriving from another patient's history page while this page is open
  // picks that patient.
  useEffect(() => {
    if (initialPatientId != null) {
      setMode('existing');
      setPatientId(initialPatientId);
    }
  }, [initialPatientId]);

  /// The chart picked, fetched by id: it may be anyone at the clinic, not
  /// only someone in the current search results.
  const selectedAsync = usePatientById(patientId ?? '', patientId != null);
  const selected = patientId == null ? null : selectedAsync.value ?? null;

  const canSubmit = service != null && doctor != null && slot != null && (mode === 'new' || selected != null);

  /// The next walk-in starts clean.
  const reset = () => {
    setMode('existing');
    setPatientId(null);
    setQuery('');
    setService(null);
    setDoctor(null);
    setSlot(null);
    setName('');
    setPhone('');
    setErrors({});
  };

  const submit = async () => {
    const isNew = mode === 'new';
    if (isNew) {
      const e = {
        name: name.trim() === '' ? 'Name is required' : undefined,
        phone: phone.trim() === '' ? 'Phone is required' : undefined,
      };
      setErrors(e);
      if (e.name != null || e.phone != null) return;
    }
    const patient = isNew ? null : selected;
    if (service == null || doctor == null || slot == null) return;
    if (!isNew && patient == null) return;
    if (clinicId == null) {
      overlay.snack('Still loading the clinic. Try again in a moment.');
      return;
    }
    const who = patient?.name ?? name.trim();
    setBusy(true);
    try {
      if (patient != null) {
        await actions.book({ clinicId, patientId: patient.id, doctorId: doctor.id, serviceId: service.id, serviceName: service.name, scheduledAt: slot, status: 'confirmed' });
      } else {
        // One RPC, one transaction. Registering the chart and booking
        // against it as two separate writes left an orphan patient behind
        // whenever the booking lost the double-booking race.
        await actions.bookWalkIn({ clinicId, fullName: who, phone: phone.trim(), doctorId: doctor.id, serviceId: service.id, serviceName: service.name, scheduledAt: slot });
        invalidatePatientLists(qc);
      }
      await overlay.showDialog<void>(
        (close) => (
          <>
            <Dialog.Title>Booked!</Dialog.Title>
            <Dialog.Content>
              <Text>
                {who} is booked for {service.name} at {format(slot, 'h:mm a')} with Dr. {doctor.name}.
              </Text>
            </Dialog.Content>
            <Dialog.Actions>
              <Button mode="contained" onPress={() => close()}>
                Done
              </Button>
            </Dialog.Actions>
          </>
        ),
        { dismissible: false },
      );
      reset();
      nav.go('/check-in');
    } catch (e) {
      // Most likely the time was taken meanwhile: refetch, and pick again.
      void qc.invalidateQueries({ queryKey: ['slots'] });
      setSlot(null);
      overlay.snack(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const who = (
    <View>
      <Heading>Patient</Heading>
      <SegmentedButtons
        value={mode}
        onValueChange={(v) => setMode(v as PatientMode)}
        buttons={[
          { value: 'existing', icon: 'person-search', label: 'On file' },
          { value: 'new', icon: 'person-add-alt', label: 'New patient' },
        ]}
      />
      <View style={{ height: 12 }} />
      {mode === 'existing' ? (
        <ExistingPatient
          selected={selected}
          query={query}
          onQuery={setQuery}
          onPick={(p) => {
            setPatientId(p?.id ?? null);
            setQuery('');
          }}
          onRegister={(typed) => {
            // Carry what was typed over, so it is not typed twice.
            if (/^[\d\s+()-]+$/.test(typed)) setPhone(typed);
            else setName(typed);
            setMode('new');
          }}
        />
      ) : (
        <NewPatient
          name={name}
          phone={phone}
          errors={errors}
          onName={setName}
          onPhone={setPhone}
          onUse={(p) => {
            setMode('existing');
            setPatientId(p.id);
          }}
        />
      )}
      <Heading top={24}>Service</Heading>
      <Wrap align="flex-start">
        {services.map((s) => {
          const on = s.id === service?.id;
          return (
            <Chip
              key={s.id}
              mode="outlined"
              selected={on}
              showSelectedCheck
              style={on ? { backgroundColor: colors.primaryContainer } : undefined}
              onPress={() => {
                setService(s);
                setSlot(null);
              }}
            >
              {s.name}
            </Chip>
          );
        })}
      </Wrap>
    </View>
  );

  const when = (
    <View>
      <Heading top={24}>Doctor</Heading>
      <View style={{ gap: 8 }}>
        {doctors.map((d) => {
          const on = doctor?.id === d.id;
          return (
            <AppCard key={d.id} style={{ borderColor: on ? colors.primary : colors.outlineVariant, borderWidth: on ? 2 : 1 }}>
              <ListTile
                onPress={() => {
                  setDoctor(d);
                  setSlot(null);
                }}
                leading={<DoctorAvatar doctor={d} />}
                title={<Text style={{ fontWeight: '600' }}>Dr. {d.name}</Text>}
                subtitle={d.specialty}
                trailing={on ? <Icon name="check-circle" color={colors.primary} /> : undefined}
              />
            </AppCard>
          );
        })}
      </View>
      {/* Today's free times for this doctor and service. */}
      <Heading top={24}>Time</Heading>
      {doctor != null ? (
        <TodaySlots doctor={doctor} service={service} selected={slot} onSelect={setSlot} />
      ) : (
        <Text style={{ color: colors.onSurfaceVariant }}>Choose a doctor to see their free times.</Text>
      )}
      <View style={{ height: 32 }} />
    </View>
  );

  const book = (
    <Button mode="contained" icon="add-circle-outline" disabled={!canSubmit || busy} onPress={() => void submit()} contentStyle={{ height: 48 }}>
      {busy ? <ActivityIndicator size={18} /> : 'Book Walk-In Appointment'}
    </Button>
  );

  return (
    // Two steps side by side on a tablet held sideways: who and what on the
    // left, with whom and when on the right, next to Book.
    <Page title="Walk-In Booking" maxWidth={ContentWidth.detail}>
      <SplitColumns
        narrow={
          <>
            {who}
            {when}
            {book}
          </>
        }
        start={who}
        end={
          <>
            {when}
            {book}
          </>
        }
      />
    </Page>
  );
}

function Heading({ children, top = 0 }: { children: ReactNode; top?: number }) {
  return (
    <Text variant="titleMedium" style={{ fontWeight: '700', marginTop: top, marginBottom: 12 }}>
      {children}
    </Text>
  );
}

function TodaySlots({ doctor, service, selected, onSelect }: { doctor: Doctor; service: Service | null; selected: Date | null; onSelect: (s: Date) => void }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const [today] = useState(() => startOfDay(new Date()));
  const slots = useAvailableSlots({ doctorId: doctor.id, day: today, serviceId: service?.id ?? null, ignore: null });
  return (
    <AsyncView value={slots} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['slots'] })}>
      {(slots) =>
        slots.length === 0 ? (
          <Text style={{ color: colors.onSurfaceVariant }}>Dr. {doctor.name} has no free time left today.</Text>
        ) : (
          <Wrap align="flex-start">
            {slots.map((s) => {
              const on = s.getTime() === selected?.getTime();
              return (
                <Chip key={s.getTime()} mode="outlined" selected={on} style={on ? { backgroundColor: colors.primaryContainer } : undefined} onPress={() => onSelect(s)}>
                  {format(s, 'h:mm a')}
                </Chip>
              );
            })}
          </Wrap>
        )
      }
    </AsyncView>
  );
}

function ExistingPatient({
  selected,
  query,
  onQuery,
  onPick,
  onRegister,
}: {
  selected: Patient | null;
  query: string;
  onQuery: (q: string) => void;
  onPick: (p: Patient | null) => void;
  onRegister: (typed: string) => void;
}) {
  const { colors } = useAppTheme();
  const q = query.trim();
  // Searched in the database, a moment after typing stops.
  const search = usePatientSearch(q, q !== '' && selected == null);

  if (selected != null) {
    return (
      <AppCard style={{ borderColor: colors.primary, borderWidth: 2 }}>
        <ListTile
          leading={<Avatar label={selected.initials} />}
          title={<Text style={{ fontWeight: '600' }}>{selected.name}</Text>}
          subtitle={selected.phone}
          trailing={<Button onPress={() => onPick(null)}>Change</Button>}
        />
      </AppCard>
    );
  }

  const matches = search.value ?? [];
  const searching = !search.hasValue && !search.hasError;
  return (
    <View>
      <TextField value={query} onChangeText={onQuery} placeholder="Search by name or phone…" icon="search" />
      <View style={{ height: 8 }} />
      {q === '' ? (
        <Text style={{ color: colors.outline, fontSize: 13 }}>Find the patient first. Register them as new only if they are not on file.</Text>
      ) : searching ? (
        <ProgressBar indeterminate style={{ height: 2 }} />
      ) : search.hasError ? (
        <Text style={{ color: colors.error }}>{describeError(search.error)}</Text>
      ) : matches.length === 0 ? (
        <View style={{ alignItems: 'flex-start' }}>
          <Text style={{ color: colors.onSurfaceVariant }}>No patient on file matches "{q}".</Text>
          <Button icon="person-add-alt" onPress={() => onRegister(q)}>
            Register as a new patient
          </Button>
        </View>
      ) : (
        <View style={{ gap: 8 }}>
          {matches.map((p) => (
            <AppCard key={p.id}>
              <ListTile
                leading={<Avatar label={p.initials} />}
                title={<Text style={{ fontWeight: '600' }}>{p.name}</Text>}
                subtitle={p.phone}
                onPress={() => onPick(p)}
              />
            </AppCard>
          ))}
        </View>
      )}
    </View>
  );
}

function NewPatient({
  name,
  phone,
  errors,
  onName,
  onPhone,
  onUse,
}: {
  name: string;
  phone: string;
  errors: { name?: string; phone?: string };
  onName: (v: string) => void;
  onPhone: (v: string) => void;
  onUse: (p: Patient) => void;
}) {
  const { colors } = useAppTheme();
  // Once a full number is typed, look it up: a "new" walk-in is often
  // already on file.
  const typed = phone.trim();
  const longEnough = typed.replace(/\D/g, '').length >= 7;
  const search = usePatientSearch(typed, longEnough);
  const sameNumber = longEnough ? (search.value ?? []).filter((p) => p.hasPhone(typed)) : [];
  const on = colors.onTertiaryContainer;
  return (
    <View>
      <TextField label="Full Name" value={name} onChangeText={onName} icon="person-outline" autoCapitalize="words" error={errors.name} />
      <View style={{ height: 12 }} />
      <TextField label="Phone Number" value={phone} onChangeText={onPhone} icon="phone" keyboardType="phone-pad" error={errors.phone} />
      {sameNumber.length > 0 && (
        <View style={{ marginTop: 12, padding: 12, borderRadius: 12, backgroundColor: colors.tertiaryContainer }}>
          <Text style={{ fontWeight: '600', color: on }}>Already on file with this number</Text>
          {sameNumber.map((p) => (
            <ListTile
              key={p.id}
              paddingHorizontal={0}
              title={<Text style={{ color: on }}>{p.name}</Text>}
              subtitle={<Text style={{ color: on }}>{p.phone}</Text>}
              trailing={
                <Button mode="contained-tonal" onPress={() => onUse(p)}>
                  Use
                </Button>
              }
            />
          ))}
        </View>
      )}
    </View>
  );
}
