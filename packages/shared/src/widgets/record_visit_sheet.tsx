import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, ProgressBar, SegmentedButtons, Text } from 'react-native-paper';

import type { Doctor } from '../models/doctor';
import type { Patient } from '../models/patient';
import type { Service } from '../models/service';
import { useAppointmentActions } from '../queries/appointments';
import { invalidatePatientLists, useDoctors, usePatientSearch, useServices } from '../queries/catalog';
import { useCurrentClinicId } from '../queries/clinic';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { SelectField, TextField, useDatePicker, useTimePicker } from '../ui/fields';
import { Icon } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { isSameDay, startOfDay } from '../util/dates';

/// The fallback for a visit that happened but never went through the app —
/// nobody booked or checked it in on the day. The front desk and admins
/// enter it afterwards, for [patient] or, without one, for anyone on file or
/// someone new. Answers whether a visit was recorded.
///
/// A doctor's or admin's record goes in completed. The front desk's stays
/// confirmed for one of them to complete, since the database lets only
/// clinicians complete a visit. It may not overlap another visit of that
/// doctor's, and nobody is notified.
export function useRecordVisitSheet(): (patient?: Patient | null) => Promise<boolean> {
  const overlay = useOverlay();
  return async (patient) => {
    const recorded = await overlay.showSheet<string>((close) => <RecordVisitSheet patient={patient ?? null} close={close} />);
    if (recorded == null) return false;
    overlay.snack(recorded);
    return true;
  };
}

function RecordVisitSheet({ patient: given, close }: { patient: Patient | null; close: Close<string> }) {
  const { colors } = useAppTheme();
  const actions = useAppointmentActions();
  const qc = useQueryClient();
  const clinicId = useCurrentClinicId();
  const doctors = useDoctors();
  const services = useServices();
  const pickDate = useDatePicker();
  const pickTime = useTimePicker();

  const [patient, setPatient] = useState<Patient | null>(given);
  const [isNew, setIsNew] = useState(false);
  const [query, setQuery] = useState('');
  const [newName, setNewName] = useState('');
  const [newPhone, setNewPhone] = useState('');
  const [otherService, setOtherService] = useState('');
  // Usually the visit was earlier today: start there, at the last half hour.
  const [day, setDay] = useState(() => startOfDay(new Date()));
  const [time, setTime] = useState(() => {
    const now = new Date();
    return `${String(now.getHours()).padStart(2, '0')}:${now.getMinutes() < 30 ? '00' : '30'}`;
  });
  const [doctor, setDoctor] = useState<Doctor | null>(null);
  /// Null with [isOther] set: a service not in the catalogue, named in
  /// [otherService].
  const [service, setService] = useState<Service | null>(null);
  const [isOther, setIsOther] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [hh, mm] = time.split(':').map(Number);
  const when = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hh, mm);
  const serviceName = isOther ? otherService.trim() : service?.name ?? '';
  const hasPatient = isNew ? newName.trim() !== '' && newPhone.trim() !== '' : patient != null;
  const canSave = hasPatient && doctor != null && serviceName !== '' && !busy;

  const phone = newPhone.trim();
  const phoneReady = isNew && phone.replace(/\D/g, '').length >= 7;
  const phoneSearch = usePatientSearch(phone, phoneReady);
  const sameNumber = phoneReady ? (phoneSearch.value ?? []).filter((p) => p.hasPhone(phone)) : [];
  const search = usePatientSearch(query.trim(), query.trim() !== '');

  const save = async () => {
    if (doctor == null) return;
    if (when.getTime() > Date.now()) {
      setError('That time has not come yet. Book it instead.');
      return;
    }
    if (clinicId == null) {
      setError('Still loading the clinic. Try again in a moment.');
      return;
    }
    const chart = isNew ? null : patient;
    const name = chart?.name ?? newName.trim();
    setBusy(true);
    setError(null);
    try {
      await actions.recordMissedVisit({
        clinicId,
        patientId: chart?.id,
        newPatientName: isNew ? name : null,
        newPatientPhone: isNew ? newPhone.trim() : null,
        doctorId: doctor.id,
        serviceId: isOther ? null : service?.id,
        serviceName,
        scheduledAt: when,
        complete: true,
      });
      if (isNew) invalidatePatientLists(qc);
      close(`Visit on ${format(when, 'MMM d · h:mm a')} recorded for ${name}`);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  /// Search first, as at the walk-in desk: registering someone already on
  /// file splits their history in two.
  const patientPicker = () => {
    const header = (
      <SegmentedButtons
        value={isNew ? 'new' : 'file'}
        onValueChange={(v) => setIsNew(v === 'new')}
        buttons={[
          { value: 'file', icon: 'person-search', label: 'On file' },
          { value: 'new', icon: 'person-add-alt', label: 'New patient' },
        ]}
      />
    );
    if (isNew) {
      return (
        <>
          {header}
          <TextField style={{ marginTop: 12 }} label="Full Name" icon="person-outline" autoCapitalize="words" value={newName} onChangeText={setNewName} />
          <TextField style={{ marginTop: 12 }} label="Phone Number" icon="phone" keyboardType="phone-pad" value={newPhone} onChangeText={setNewPhone} />
          {sameNumber.map((p) => (
            <ListTile
              key={p.id}
              paddingHorizontal={0}
              leading={<Icon name="info-outline" color={colors.tertiary} />}
              title={`${p.name} is on file with this number`}
              trailing={
                <Button
                  mode="contained-tonal"
                  onPress={() => {
                    setIsNew(false);
                    setPatient(p);
                  }}
                >
                  Use
                </Button>
              }
            />
          ))}
        </>
      );
    }
    if (patient != null) {
      return (
        <>
          {header}
          <AppCard style={{ marginTop: 12 }}>
            <ListTile
              title={<Text style={{ fontWeight: '600' }}>{patient.name}</Text>}
              subtitle={patient.phone}
              trailing={<Button onPress={() => setPatient(null)}>Change</Button>}
            />
          </AppCard>
        </>
      );
    }
    const q = query.trim();
    const matches = q === '' ? [] : search.value ?? [];
    return (
      <>
        {header}
        <TextField style={{ marginTop: 12 }} icon="search" placeholder="Search by name or phone…" value={query} onChangeText={setQuery} />
        {q !== '' && !search.hasValue && !search.hasError ? (
          <ProgressBar indeterminate style={{ height: 2 }} />
        ) : q !== '' && search.hasError ? (
          <Text style={{ color: colors.error }}>{describeError(search.error)}</Text>
        ) : q !== '' && matches.length === 0 ? (
          <Text style={{ marginTop: 8, color: colors.onSurfaceVariant }}>No patient on file matches "{q}".</Text>
        ) : (
          matches.slice(0, 5).map((p) => (
            <ListTile
              key={p.id}
              paddingHorizontal={0}
              title={p.name}
              subtitle={p.phone}
              onPress={() => {
                setPatient(p);
                setQuery('');
              }}
            />
          ))
        )}
      </>
    );
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        Manually add visit
      </Text>
      <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        For a visit that happened but was never entered. Nobody is notified. It is saved as completed.
      </Text>
      <View style={{ height: 16 }} />
      {given == null && (
        <>
          {patientPicker()}
          <View style={{ height: 16 }} />
        </>
      )}
      <View style={{ flexDirection: 'row', gap: 8 }}>
        <Button
          mode="outlined"
          icon="calendar-today"
          style={{ flex: 1 }}
          contentStyle={{ height: 48 }}
          onPress={async () => {
            const today = startOfDay(new Date());
            const picked = await pickDate({
              initial: day,
              first: new Date(today.getFullYear() - 5, 0, 1),
              last: today,
              title: 'When was the visit?',
            });
            if (picked) setDay(picked);
          }}
        >
          {isSameDay(day, new Date()) ? 'Today' : format(day, 'MMM d, y')}
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
      <View style={{ height: 16 }} />
      <AsyncView value={doctors} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['doctors'] })}>
        {(list) => (
          <SelectField
            label="Doctor"
            value={doctor?.id ?? null}
            options={list.map((d) => ({ value: d.id, label: `Dr. ${d.name}` }))}
            onChange={(id) => setDoctor(list.find((d) => d.id === id) ?? null)}
          />
        )}
      </AsyncView>
      <View style={{ height: 16 }} />
      <AsyncView value={services} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['services'] })}>
        {(list) => (
          <SelectField
            label="Service"
            value={isOther ? '' : service?.id ?? null}
            options={[...list.map((s) => ({ value: s.id, label: s.name })), { value: '', label: 'Other…' }]}
            onChange={(id) => {
              setIsOther(id === '');
              setService(id === '' ? null : list.find((s) => s.id === id) ?? null);
            }}
          />
        )}
      </AsyncView>
      {isOther && (
        <TextField
          style={{ marginTop: 12 }}
          label="What was done"
          helperText="Counts as a 30-minute visit."
          autoFocus
          autoCapitalize="sentences"
          value={otherService}
          onChangeText={setOtherService}
        />
      )}
      {error != null && <Text style={{ marginTop: 12, color: colors.error }}>{error}</Text>}
      <Button mode="contained" disabled={!canSave} onPress={save} style={{ marginTop: 20 }} contentStyle={{ height: 52 }}>
        {busy ? <ActivityIndicator size={20} /> : 'Add visit'}
      </Button>
    </SheetScroll>
  );
}
