import {
  AppCard,
  AsyncView,
  ContentWidth,
  Icon,
  ListTile,
  Page,
  SelectField,
  type Service,
  TextField,
  describeError,
  invalidateCatalog,
  useAppTheme,
  useCatalogue,
  useCurrentClinicId,
  useOverlay,
  useRepository,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

import { EditorDialog, SwitchRow, Tag } from './roster_widgets';

/// `/:clinic/settings/services` — what patients can book, how long each
/// takes, and what it costs.
///
/// The duration is what a booking blocks on the doctor's calendar, so it
/// decides which times `available_slots` offers. Services are retired, not
/// deleted: past visits point at them.
export function ServicesScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const catalogue = useCatalogue();

  const edit = async (service: Service | null) => {
    const saved = await overlay.showDialog<boolean>((close) => <ServiceEditor service={service} close={close} />, { dismissible: false });
    if (saved) invalidateCatalog(qc);
  };

  return (
    <Page title="Services" back="/settings" maxWidth={ContentWidth.list} fab={{ icon: 'add', label: 'Add service', onPress: () => void edit(null) }}>
      <AsyncView value={catalogue} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['catalogue'] })}>
        {(services) =>
          services.length === 0 ? (
            <Text style={{ padding: 32, textAlign: 'center' }}>No services yet. Add what patients can book.</Text>
          ) : (
            <View style={{ gap: 8 }}>
              {services.map((s) => (
                <AppCard key={s.id}>
                  <ListTile
                    onPress={() => void edit(s)}
                    leading={<Icon name="medical-services" color={s.isActive ? colors.primary : colors.outline} />}
                    title={<Text style={{ fontWeight: '600', color: s.isActive ? undefined : colors.outline }}>{s.name}</Text>}
                    subtitle={[`${s.durationMinutes} min`, s.priceLabel ?? 'No price set'].join(' · ')}
                    trailing={s.isActive ? <Icon name="edit" /> : <Tag label="Retired" />}
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

const durations = [10, 15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240];

function priceText(p: number | null | undefined): string {
  if (p == null) return '';
  return p === Math.round(p) ? p.toFixed(0) : p.toFixed(2);
}

function ServiceEditor({ service, close }: { service: Service | null; close: (saved?: boolean) => void }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const isNew = service == null;
  const [name, setName] = useState(service?.name ?? '');
  const [price, setPrice] = useState(() => priceText(service?.price));
  const [minutes, setMinutes] = useState(service?.durationMinutes ?? 30);
  const [active, setActive] = useState(service?.isActive ?? true);
  const [fieldErrors, setFieldErrors] = useState<{ name?: string; price?: string }>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const options = [...new Set([...durations, minutes])].sort((a, b) => a - b);

  const save = async () => {
    if (busy) return;
    const t = price.trim().replace(/,/g, '');
    const parsed = t === '' ? null : Number(t);
    const errs = {
      name: name.trim() === '' ? 'Enter a name' : undefined,
      price: parsed != null && (Number.isNaN(parsed) || parsed < 0) ? 'Enter an amount, or leave it blank' : undefined,
    };
    setFieldErrors(errs);
    if (errs.name != null || errs.price != null) return;
    setBusy(true);
    setError(null);
    try {
      if (service == null) {
        await repo.addService({ clinicId: clinicId!, name: name.trim(), durationMinutes: minutes, price: parsed });
      } else {
        await repo.updateService(service.id, { name: name.trim(), duration_minutes: minutes, price: parsed, is_active: active });
      }
      close(true);
    } catch (e) {
      const message = describeError(e);
      setError(message.includes('services_clinic_id_name_key') ? 'There is already a service with that name.' : message);
      setBusy(false);
    }
  };

  return (
    <EditorDialog
      title={isNew ? 'Add service' : 'Edit service'}
      width={400}
      saveLabel={isNew ? 'Add' : 'Save'}
      busy={busy}
      onCancel={() => close(false)}
      onSave={() => void save()}
    >
      <TextField label="Name" value={name} onChangeText={setName} autoFocus={isNew} autoCapitalize="words" error={fieldErrors.name} />
      <SelectField
        style={{ marginTop: 12 }}
        label="Takes"
        helperText="How long it blocks the doctor's calendar."
        value={minutes}
        options={options.map((m) => ({ value: m, label: `${m} minutes` }))}
        onChange={setMinutes}
      />
      <TextField
        style={{ marginTop: 12 }}
        label="Price (optional)"
        prefix="₱ "
        keyboardType="decimal-pad"
        helperText="Shown to patients when they book."
        value={price}
        onChangeText={setPrice}
        error={fieldErrors.price}
      />
      {!isNew && (
        <View style={{ marginTop: 12 }}>
          <SwitchRow title="Bookable" subtitle="Off retires it: no new bookings. Past and booked visits keep it." value={active} onChange={setActive} />
          {service.durationMinutes !== minutes && (
            <Text style={{ color: colors.onSurfaceVariant, fontSize: 12 }}>
              A new length applies to new bookings. Visits already booked keep the time they were booked for.
            </Text>
          )}
        </View>
      )}
      {error != null && <Text style={{ marginTop: 12, color: colors.error }}>{error}</Text>}
    </EditorDialog>
  );
}
