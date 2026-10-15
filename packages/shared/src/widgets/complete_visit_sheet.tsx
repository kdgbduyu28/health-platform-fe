import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Checkbox, Divider, IconButton, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import type { Invoice } from '../models/invoice';
import { formatPeso } from '../models/money';
import type { Service } from '../models/service';
import { refreshAppointments } from '../queries/appointments';
import { invalidateBilling, useAppointmentInvoice } from '../queries/billing';
import { useCatalogue } from '../queries/catalog';
import { useRepository } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { ListTile } from '../ui/kit';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';

/// Marks a visit done: asks which services were performed, shows what they
/// come to at the clinic's prices, and saves both — the visit completed, the
/// services on its bill. Anyone on staff may.
///
/// Answers the visit's bill id when it has one, '' when saved without a bill
/// (no services ticked), or null if cancelled or refused. The refusal is
/// shown in the database's words.
///
/// On a visit already completed it corrects the services instead.
export function useCompleteVisitSheet(): (appointment: Appointment) => Promise<string | null> {
  const overlay = useOverlay();
  return async (appointment) => {
    const result = await overlay.showSheet<string>((close) => <CompleteVisitSheet appointment={appointment} close={close} />);
    if (result == null) return null;
    overlay.snack(appointment.status === 'completed' ? 'Services updated' : 'Visit done');
    return result;
  };
}

function prefill(appointment: Appointment, bill: Invoice | null): Map<string, number> {
  const fromBill = new Map<string, number>();
  for (const i of bill?.items ?? []) if (i.serviceId != null) fromBill.set(i.serviceId, i.quantity);
  if (fromBill.size > 0) return fromBill;
  return new Map(appointment.serviceId != null ? [[appointment.serviceId, 1]] : []);
}

function CompleteVisitSheet({ appointment: a, close }: { appointment: Appointment; close: Close<string> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const qc = useQueryClient();
  const billAsync = useAppointmentInvoice(a.id);
  const servicesAsync = useCatalogue();
  const correcting = a.status === 'completed';
  /// Service id → how many times. Null until prefilled from the bill (or the
  /// booked service), so the prefill happens once.
  const [pickedState, setPicked] = useState<Map<string, number> | null>(null);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Wait for the bill before prefilling from it.
  const picked = pickedState ?? (billAsync.hasValue ? prefill(a, billAsync.value ?? null) : null);
  const bill = billAsync.value ?? null;
  const locked = bill != null && !bill.isDraft;

  const total = (all: Service[]) => all.reduce((sum, s) => sum + (s.price ?? 0) * (picked?.get(s.id) ?? 0), 0);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      const id = await repo.completeVisit(a.id, picked ?? new Map());
      void invalidateBilling(qc);
      await refreshAppointments(qc);
      close(id ?? '');
    } catch (e) {
      setBusy(false);
      setError(describeError(e));
    }
  };

  const label = () => {
    const verb = correcting ? 'Save' : 'Mark done';
    const all = servicesAsync.value;
    if (locked || all == null) return verb;
    const t = total(all);
    return t > 0 ? `${verb} · ${formatPeso(t)}` : verb;
  };

  const picker = (all: Service[]) => {
    const current = picked ?? new Map<string, number>();
    // Retired services only when already on this visit.
    const offered = all.filter((s) => s.isActive || current.has(s.id));
    const q = query.toLowerCase();
    const shown = offered.filter((s) => q === '' || s.name.toLowerCase().includes(q) || current.has(s.id));
    const unpriced = offered.filter((s) => current.has(s.id) && s.price == null).map((s) => s.name);
    const change = (s: Service, n: number) => {
      const next = new Map(current);
      if (n <= 0) next.delete(s.id);
      else next.set(s.id, Math.min(999, Math.max(1, n)));
      setPicked(next);
    };
    return (
      <View>
        {offered.length > 8 && (
          <TextField icon="search" dense placeholder="Find a service…" value={query} onChangeText={(v) => setQuery(v.trim())} style={{ marginBottom: 8 }} />
        )}
        {shown.map((s) => {
          const qty = current.get(s.id) ?? 0;
          const on = qty > 0;
          return (
            <ListTile
              key={s.id}
              dense
              paddingHorizontal={0}
              onPress={() => change(s, on ? 0 : 1)}
              leading={<Checkbox.Android status={on ? 'checked' : 'unchecked'} onPress={() => change(s, on ? 0 : 1)} />}
              title={s.name}
              subtitle={<Text style={{ color: s.price == null ? colors.error : colors.onSurfaceVariant }}>{s.priceLabel ?? 'No price set'}</Text>}
              trailing={
                on ? (
                  <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <IconButton icon="remove-circle-outline" size={20} accessibilityLabel="One fewer" onPress={() => change(s, qty - 1)} />
                    <Text style={{ fontWeight: '600' }}>{qty}</Text>
                    <IconButton icon="add-circle-outline" size={20} accessibilityLabel="One more" disabled={qty >= 999} onPress={() => change(s, qty + 1)} />
                  </View>
                ) : undefined
              }
            />
          );
        })}
        <Divider style={{ marginVertical: 10 }} />
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={{ flex: 1, color: colors.onSurfaceVariant }}>Total</Text>
          <Text style={{ fontSize: 20, fontWeight: '700' }}>{formatPeso(total(all))}</Text>
        </View>
        {unpriced.length > 0 && (
          <Text style={{ marginTop: 4, fontSize: 12, color: colors.error }}>
            No price set for {unpriced.join(', ')} — it goes on the bill at ₱0. Set prices under Billing › Prices.
          </Text>
        )}
        {current.size === 0 && (
          <Text style={{ marginTop: 4, fontSize: 12, color: colors.onSurfaceVariant }}>
            Nothing ticked: the visit is marked done without a bill.
          </Text>
        )}
      </View>
    );
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        {correcting ? 'Services done' : 'Mark visit done'}
      </Text>
      <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        {a.patient.name} · booked for {a.service}
      </Text>
      <View style={{ height: 12 }} />
      {locked ? (
        <Text style={{ color: colors.onSurfaceVariant }}>
          This visit's bill ({bill.label}) has been issued, so the services on it no longer change here.{' '}
          {correcting ? '' : 'The visit will still be marked done.'}
        </Text>
      ) : (
        <AsyncView value={servicesAsync} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['catalogue'] })}>
          {picker}
        </AsyncView>
      )}
      {error != null && <Text style={{ marginTop: 8, color: colors.error }}>{error}</Text>}
      <Button
        mode="contained"
        icon={busy ? undefined : 'task-alt'}
        disabled={busy || picked == null || (correcting && locked)}
        onPress={save}
        style={{ marginTop: 12 }}
        contentStyle={{ height: 52 }}
      >
        {busy ? <ActivityIndicator size={18} /> : label()}
      </Button>
    </SheetScroll>
  );
}
