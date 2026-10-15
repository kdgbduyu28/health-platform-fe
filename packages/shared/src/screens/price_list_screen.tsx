import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Dialog, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import type { Service } from '../models/service';
import { invalidateCatalog, useCatalogue } from '../queries/catalog';
import { useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { amountInput, parseAmount } from '../widgets/ledger_view';

/// What each service costs, for the front desk and admins. Marking a visit
/// done puts its services on the bill at these prices.
///
/// Prices only: adding, renaming and retiring services stays in the admin
/// app's Clinic › Services. A new price applies to bills drafted from now
/// on; lines already on a bill keep theirs.
export function PriceListScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const catalogue = useCatalogue();
  const [query, setQuery] = useState('');

  const edit = async (s: Service) => {
    const saved = await overlay.showDialog<boolean>((close) => <PriceDialog service={s} close={close} />);
    if (saved) invalidateCatalog(qc);
  };

  return (
    <Page title="Prices" maxWidth={ContentWidth.list} back="/billing">
      <AsyncView value={catalogue} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['catalogue'] })}>
        {(all) => {
          const active = all.filter((s) => s.isActive);
          const q = query.toLowerCase();
          const shown = active.filter((s) => q === '' || s.name.toLowerCase().includes(q));
          const unpriced = active.filter((s) => s.price == null).length;
          if (active.length === 0) {
            return <Text style={{ padding: 32, textAlign: 'center' }}>No services yet. An admin adds them under Clinic › Services.</Text>;
          }
          return (
            <View>
              {unpriced > 0 && (
                <Text style={{ marginBottom: 8, color: colors.error }}>
                  {unpriced} {unpriced === 1 ? 'service has' : 'services have'} no price yet. They go on bills at ₱0 until one is set.
                </Text>
              )}
              {active.length > 8 && (
                <TextField style={{ marginBottom: 8 }} icon="search" placeholder="Find a service…" value={query} onChangeText={(v) => setQuery(v.trim())} />
              )}
              {shown.map((s) => (
                <AppCard key={s.id} style={{ marginBottom: 8 }}>
                  <ListTile
                    onPress={() => void edit(s)}
                    leading={<Icon name="sell" color={colors.onSurfaceVariant} />}
                    title={<Text style={{ fontWeight: '600' }}>{s.name}</Text>}
                    subtitle={`${s.durationMinutes} min`}
                    trailing={
                      <Text style={{ fontSize: 16, fontWeight: '700', color: s.price == null ? colors.error : undefined }}>{s.priceLabel ?? 'Set price'}</Text>
                    }
                  />
                </AppCard>
              ))}
            </View>
          );
        }}
      </AsyncView>
    </Page>
  );
}

function PriceDialog({ service, close }: { service: Service; close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const p = service.price;
  const [price, setPrice] = useState(p == null ? '' : p === Math.round(p) ? p.toFixed(0) : p.toFixed(2));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const parsed = parseAmount(price);
  const valid = price.trim() === '' || (parsed != null && parsed >= 0);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await repo.setServicePrice(service.id, price.trim() === '' ? null : parsed);
      close(true);
    } catch (e) {
      setBusy(false);
      setError(describeError(e));
    }
  };

  return (
    <>
      <Dialog.Title>{service.name}</Dialog.Title>
      <Dialog.Content>
        <TextField
          label="Price"
          prefix="₱"
          autoFocus
          keyboardType="decimal-pad"
          helperText="Empty clears it. Bills already drafted keep their price."
          value={price}
          onChangeText={(t) => setPrice(amountInput(t))}
          onSubmit={() => valid && !busy && void save()}
        />
        {error != null && <Text style={{ marginTop: 8, color: colors.error }}>{error}</Text>}
      </Dialog.Content>
      <Dialog.Actions>
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
        <Button mode="contained" disabled={!valid || busy} onPress={save}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}
