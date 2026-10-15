import { useState } from 'react';
import { ProgressBar, SegmentedButtons, Text, Button } from 'react-native-paper';

import type { Patient } from '../models/patient';
import { usePatientSearch } from '../queries/catalog';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';

/// Who a visit is for: someone on file, found by name or phone, or someone
/// new by name and phone.
export type ChosenPatient = { patient: Patient | null; isNew: boolean; newName: string; newPhone: string };

export const noPatientChosen: ChosenPatient = { patient: null, isNew: false, newName: '', newPhone: '' };

export function hasChosenPatient(c: ChosenPatient): boolean {
  return c.isNew ? c.newName.trim() !== '' && c.newPhone.trim() !== '' : c.patient != null;
}

/// Search first, as at the walk-in desk: registering someone already on
/// file splits their history in two. A new patient's number is checked
/// against the files as it is typed.
export function PatientChooser({ value, onChange }: { value: ChosenPatient; onChange: (next: ChosenPatient) => void }) {
  const { colors } = useAppTheme();
  const [query, setQuery] = useState('');
  const phone = value.newPhone.trim();
  const phoneReady = value.isNew && phone.replace(/\D/g, '').length >= 7;
  const phoneSearch = usePatientSearch(phone, phoneReady);
  const sameNumber = phoneReady ? (phoneSearch.value ?? []).filter((p) => p.hasPhone(phone)) : [];
  const q = query.trim();
  const search = usePatientSearch(q, q !== '');
  const set = (patch: Partial<ChosenPatient>) => onChange({ ...value, ...patch });

  const header = (
    <SegmentedButtons
      value={value.isNew ? 'new' : 'file'}
      onValueChange={(v) => set({ isNew: v === 'new' })}
      buttons={[
        { value: 'file', icon: 'person-search', label: 'On file' },
        { value: 'new', icon: 'person-add-alt', label: 'New patient' },
      ]}
    />
  );

  if (value.isNew) {
    return (
      <>
        {header}
        <TextField style={{ marginTop: 12 }} label="Full Name" icon="person-outline" autoCapitalize="words" value={value.newName} onChangeText={(t) => set({ newName: t })} />
        <TextField style={{ marginTop: 12 }} label="Phone Number" icon="phone" keyboardType="phone-pad" value={value.newPhone} onChangeText={(t) => set({ newPhone: t })} />
        {sameNumber.map((p) => (
          <ListTile
            key={p.id}
            paddingHorizontal={0}
            leading={<Icon name="info-outline" color={colors.tertiary} />}
            title={`${p.name} is on file with this number`}
            trailing={
              <Button mode="contained-tonal" onPress={() => set({ isNew: false, patient: p })}>
                Use
              </Button>
            }
          />
        ))}
      </>
    );
  }
  if (value.patient != null) {
    return (
      <>
        {header}
        <AppCard style={{ marginTop: 12 }}>
          <ListTile
            title={<Text style={{ fontWeight: '600' }}>{value.patient.name}</Text>}
            subtitle={value.patient.phone}
            trailing={<Button onPress={() => set({ patient: null })}>Change</Button>}
          />
        </AppCard>
      </>
    );
  }
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
              set({ patient: p });
              setQuery('');
            }}
          />
        ))
      )}
    </>
  );
}
