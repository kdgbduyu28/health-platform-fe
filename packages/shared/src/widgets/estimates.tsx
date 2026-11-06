import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { ActivityIndicator, Button, Chip, IconButton, ProgressBar, Text } from 'react-native-paper';

import { useClinicNav } from '../app/navigation';
import { dentalCodeMeta } from '../models/dental_chart';
import { type EstimateLine, estimateStatusMeta, lineAmount, type TreatmentEstimate } from '../models/estimate';
import { formatPeso } from '../models/money';
import type { Patient } from '../models/patient';
import { useCanBill } from '../queries/billing';
import { useServices } from '../queries/catalog';
import { invalidateEstimates, useCanEstimate, useEstimate, usePatientEstimates } from '../queries/estimates';
import { useClinicChartsTeeth, useDentalEntries } from '../queries/misc';
import { useRepository } from '../state/platform';
import { useAppTheme, useReadable } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { DateField, SelectField, TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { type Close, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { addDays, startOfDay } from '../util/dates';
import { useToothNumbering } from './dental_chart';
import { amountInput, parseAmount, ReasonDialog } from './ledger_view';

/// The status as a small coloured label.
export function EstimateStatusChip({ estimate: e }: { estimate: TreatmentEstimate }) {
  const readable = useReadable();
  const meta = estimateStatusMeta[e.status];
  const expired = e.status === 'sent' && e.expired();
  const color = readable(expired ? estimateStatusMeta.void.color : meta.color);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
      <Icon name={meta.icon} size={14} color={color} />
      <Text style={{ fontSize: 12, fontWeight: '600', color }}>{expired ? 'Expired' : e.invoiceId != null ? 'Accepted · billed' : meta.label}</Text>
    </View>
  );
}

/// An estimate as both sides read it: its lines, the total, how long it
/// holds, the notes.
export function EstimateView({ estimate: e }: { estimate: TreatmentEstimate }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ gap: 8 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
        <Text style={{ flex: 1, fontWeight: '700', fontSize: 16 }}>{e.title ?? 'Treatment estimate'}</Text>
        <EstimateStatusChip estimate={e} />
      </View>
      <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>
        {[
          format(e.sentAt ?? e.createdAt, 'MMM d, y'),
          ...(e.validUntil != null ? [`valid until ${format(e.validUntil, 'MMM d, y')}`] : []),
        ].join(' · ')}
      </Text>
      {e.status === 'void' && e.voidReason != null && <Text style={{ fontSize: 12, color: colors.error }}>Void: {e.voidReason}</Text>}
      <View style={{ borderTopWidth: 1, borderTopColor: colors.outlineVariant }}>
        {e.lines.map((l, n) => (
          <View key={l.id ?? n} style={{ flexDirection: 'row', gap: 8, paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: colors.outlineVariant }}>
            <Text style={{ flex: 1 }}>{l.description}</Text>
            {l.quantity > 1 && <Text style={{ color: colors.onSurfaceVariant }}>{`${l.quantity} × ${formatPeso(l.unitPrice)}`}</Text>}
            <Text style={{ width: 100, textAlign: 'right', fontWeight: '600' }}>{formatPeso(lineAmount(l))}</Text>
          </View>
        ))}
      </View>
      <View style={{ flexDirection: 'row' }}>
        <Text style={{ flex: 1, fontWeight: '700' }}>Total</Text>
        <Text style={{ fontWeight: '700', fontSize: 16 }}>{formatPeso(e.total)}</Text>
      </View>
      {e.notes != null && e.notes.trim() !== '' && <Text style={{ color: colors.onSurfaceVariant }}>{e.notes}</Text>}
      <Text style={{ fontSize: 11, color: colors.outline }}>
        An estimate, not a bill: the final amount may change if the treatment does.
      </Text>
    </View>
  );
}

/// A chart's estimates, for staff: write one from the planned work, send it,
/// record the patient's answer, bill an accepted one.
export function EstimatesSection({ patient }: { patient: Patient }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const allowed = useCanEstimate().value ?? false;
  const list = usePatientEstimates(patient.id);
  if (!allowed) return null;

  const open = (e: TreatmentEstimate | null) =>
    void overlay.showPage((close) =>
      e == null || e.isDraft ? <EstimateEditor patient={patient} estimate={e} close={close} /> : <EstimateDetail patient={patient} estimateId={e.id} close={close} />,
    );

  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="sell" size={16} color={colors.onSurfaceVariant} />
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>Estimates</Text>
        <Button compact icon="add" onPress={() => open(null)}>
          New
        </Button>
      </View>
      <View style={{ height: 8 }} />
      {!list.hasValue && list.hasError ? (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <Text style={{ flex: 1, color: colors.error, fontSize: 13 }}>{describeError(list.error)}</Text>
          <Button onPress={() => void invalidateEstimates(qc)}>Retry</Button>
        </View>
      ) : !list.hasValue ? (
        <ProgressBar indeterminate style={{ height: 2 }} />
      ) : list.value!.length === 0 ? (
        <Text style={{ color: colors.outline }}>No estimates yet.</Text>
      ) : (
        list.value!.map((e) => (
          <Button key={e.id} mode="text" onPress={() => open(e)} contentStyle={{ justifyContent: 'flex-start' }} style={{ marginHorizontal: -8 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <Text>{`${e.title ?? 'Estimate'} · ${formatPeso(e.total)}`}</Text>
              <EstimateStatusChip estimate={e} />
            </View>
          </Button>
        ))
      )}
    </View>
  );
}

type DraftLine = { serviceId: string | null; dentalEntryId: string | null; tooth: number | null; description: string; quantity: string; price: string };

function toLine(d: DraftLine): EstimateLine {
  return {
    serviceId: d.serviceId,
    dentalEntryId: d.dentalEntryId,
    tooth: d.tooth,
    description: d.description,
    quantity: Math.max(1, Number(d.quantity) || 1),
    unitPrice: parseAmount(d.price) ?? 0,
  };
}

function priceText(n: number | null | undefined): string {
  return n == null ? '' : String(n);
}

/// Writes or rewrites a draft. Lines come from the chart's planned work (at a
/// dental clinic), from the service list, or are typed.
function EstimateEditor({ patient, estimate, close }: { patient: Patient; estimate: TreatmentEstimate | null; close: Close<void> }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const services = useServices().value ?? [];
  const dental = useClinicChartsTeeth();
  const entries = useDentalEntries(patient.id).value ?? [];
  const [numbering] = useToothNumbering();
  const [title, setTitle] = useState(estimate?.title ?? '');
  const [notes, setNotes] = useState(estimate?.notes ?? '');
  const [validUntil, setValidUntil] = useState<Date | null>(estimate?.validUntil ?? addDays(startOfDay(new Date()), 30));
  const [lines, setLines] = useState<DraftLine[]>(
    () =>
      estimate?.lines.map((l) => ({
        serviceId: l.serviceId,
        dentalEntryId: l.dentalEntryId,
        tooth: l.tooth,
        description: l.description,
        quantity: String(l.quantity),
        price: priceText(l.unitPrice),
      })) ?? [],
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const planned = entries.filter((e) => e.status === 'planned' && !lines.some((l) => l.dentalEntryId === e.id));
  const total = lines.reduce((s, l) => s + lineAmount(toLine(l)), 0);
  const valid = lines.length > 0 && lines.every((l) => l.description.trim() !== '' && parseAmount(l.price) != null);

  const set = (n: number, patch: Partial<DraftLine>) => setLines((ls) => ls.map((l, i) => (i === n ? { ...l, ...patch } : l)));

  /// The catalogue service whose name matches a chart code, for its price.
  const serviceFor = (label: string) => services.find((s) => s.name.toLowerCase().includes(label.toLowerCase())) ?? null;

  const addPlanned = (id: string) => {
    const e = entries.find((x) => x.id === id);
    if (e == null) return;
    const s = serviceFor(dentalCodeMeta[e.code].label);
    setLines((ls) => [
      ...ls,
      { serviceId: s?.id ?? null, dentalEntryId: e.id, tooth: e.tooth, description: e.describe(numbering), quantity: '1', price: priceText(s?.price ?? 0) },
    ]);
  };

  const addService = (id: string) => {
    const s = services.find((x) => x.id === id);
    if (s == null) return;
    setLines((ls) => [...ls, { serviceId: s.id, dentalEntryId: null, tooth: null, description: s.name, quantity: '1', price: priceText(s.price ?? 0) }]);
  };

  const save = async (send: boolean) => {
    if (!valid || busy) return;
    setBusy(true);
    setError(null);
    try {
      const id = await repo.saveEstimateDraft({
        id: estimate?.id ?? null,
        clinicId: patient.clinicId,
        patientId: patient.id,
        title,
        notes,
        validUntil,
        lines: lines.map(toLine),
      });
      if (send) await repo.sendEstimate(id);
      await invalidateEstimates(qc);
      overlay.snack(send ? 'Estimate sent to the patient' : 'Draft saved');
      close();
    } catch (e) {
      setError(describeError(e));
      void invalidateEstimates(qc);
    } finally {
      setBusy(false);
    }
  };

  const discard = async () => {
    if (estimate == null) return close();
    const ok = await overlay.confirm({ title: 'Delete this draft?', confirmLabel: 'Delete', destructive: true });
    if (!ok) return;
    try {
      await repo.deleteEstimateDraft(estimate.id);
      await invalidateEstimates(qc);
      close();
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <Page
      title={estimate == null ? 'New estimate' : 'Edit estimate'}
      subtitle={patient.name}
      footer={
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, padding: 12, borderTopWidth: 1, borderTopColor: colors.outlineVariant }}>
          <Text style={{ flex: 1, fontWeight: '700', fontSize: 16 }}>{formatPeso(total)}</Text>
          <Button onPress={() => void discard()} disabled={busy}>
            {estimate == null ? 'Cancel' : 'Delete'}
          </Button>
          <Button mode="outlined" disabled={!valid || busy} onPress={() => void save(false)}>
            Save draft
          </Button>
          <Button mode="contained" icon="send" disabled={!valid || busy} onPress={() => void save(true)}>
            {busy ? <ActivityIndicator size={18} /> : 'Send'}
          </Button>
        </View>
      }
    >
      <View style={{ gap: 12 }}>
        <TextField label="Title" placeholder="Upper right root canal and crown" value={title} onChangeText={setTitle} maxLength={200} autoCapitalize="sentences" />
        <DateField label="Valid until" value={validUntil} onChange={setValidUntil} min={startOfDay(new Date())} max={addDays(new Date(), 365)} />
        {dental && planned.length > 0 && (
          <View>
            <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant, marginBottom: 6 }}>Planned on the chart</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {planned.map((e) => (
                <Chip key={e.id} icon="add" mode="outlined" onPress={() => addPlanned(e.id)}>
                  {e.describe(numbering)}
                </Chip>
              ))}
            </View>
          </View>
        )}
        {services.length > 0 && (
          <SelectField
            label="Add a service"
            value={'' as string}
            options={[{ value: '', label: 'Pick a service…', disabled: true }, ...services.map((s) => ({ value: s.id, label: s.price == null ? s.name : `${s.name} · ${formatPeso(s.price)}` }))]}
            onChange={(id) => id !== '' && addService(id)}
          />
        )}
        {lines.map((l, n) => (
          <View key={n} style={{ padding: 12, borderRadius: 12, borderWidth: 1, borderColor: colors.outlineVariant, gap: 8 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <View style={{ flex: 1 }}>
                <TextField label="Description" value={l.description} onChangeText={(v) => set(n, { description: v })} maxLength={200} />
              </View>
              <IconButton icon="delete-outline" size={20} accessibilityLabel="Remove line" onPress={() => setLines((ls) => ls.filter((_, i) => i !== n))} />
            </View>
            <View style={{ flexDirection: 'row', gap: 8 }}>
              <View style={{ width: 88 }}>
                <TextField label="Qty" keyboardType="number-pad" value={l.quantity} onChangeText={(v) => set(n, { quantity: v.replace(/[^0-9]/g, '') })} maxLength={3} />
              </View>
              <View style={{ flex: 1 }}>
                <TextField label="Price each" keyboardType="decimal-pad" prefix="₱" value={l.price} onChangeText={(v) => set(n, { price: amountInput(v) })} />
              </View>
            </View>
          </View>
        ))}
        <Button
          icon="add"
          mode="outlined"
          style={{ alignSelf: 'flex-start' }}
          onPress={() => setLines((ls) => [...ls, { serviceId: null, dentalEntryId: null, tooth: null, description: '', quantity: '1', price: '' }])}
        >
          Add a line
        </Button>
        <TextField label="Notes for the patient (optional)" value={notes} onChangeText={setNotes} multiline maxLength={2000} autoCapitalize="sentences" />
        {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
        <Text style={{ fontSize: 12, color: colors.outline }}>Once sent, an estimate cannot be changed: void it and write another.</Text>
      </View>
    </Page>
  );
}

/// A sent, decided or void estimate, for staff, with what can still be done.
function EstimateDetail({ patient, estimateId, close }: { patient: Patient; estimateId: string; close: Close<void> }) {
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const nav = useClinicNav();
  const canBill = useCanBill().value ?? false;
  const async = useEstimate(estimateId);
  const [busy, setBusy] = useState(false);

  const act = async (fn: () => Promise<void>, done: string) => {
    setBusy(true);
    try {
      await fn();
      overlay.snack(done);
    } catch (e) {
      overlay.snack(describeError(e));
    } finally {
      setBusy(false);
      void invalidateEstimates(qc);
    }
  };

  const decide = async (e: TreatmentEstimate, accept: boolean) => {
    const ok = await overlay.confirm({
      title: accept ? 'Record that the patient accepted?' : 'Record that the patient declined?',
      message: `For when ${patient.name} answers at the clinic rather than in their app.`,
      confirmLabel: accept ? 'Accepted' : 'Declined',
    });
    if (ok) await act(() => repo.decideEstimate(e.id, accept), accept ? 'Marked accepted' : 'Marked declined');
  };

  const voidIt = async (e: TreatmentEstimate) => {
    const reason = await overlay.showDialog<string>((c) => (
      <ReasonDialog title="Void this estimate?" hint="Why — e.g. plan changed" action="Void" close={c} />
    ));
    if (reason != null) await act(() => repo.voidEstimate(e.id, reason), 'Estimate voided');
  };

  const bill = async (e: TreatmentEstimate) => {
    setBusy(true);
    try {
      const invoiceId = await repo.estimateToInvoice(e.id);
      await invalidateEstimates(qc);
      void qc.invalidateQueries({ queryKey: ['invoices'] });
      void qc.invalidateQueries({ queryKey: ['patientInvoices'] });
      close();
      nav.push(`/billing/${invoiceId}`);
    } catch (err) {
      overlay.snack(describeError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Page title="Estimate" subtitle={patient.name}>
      <AsyncView value={async} padded onRetry={() => void invalidateEstimates(qc)}>
        {(e) =>
          e == null ? (
            <Text>Not found.</Text>
          ) : (
            <View style={{ gap: 16 }}>
              <EstimateView estimate={e} />
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
                {e.canDecide() && (
                  <>
                    <Button mode="contained-tonal" icon="check" disabled={busy} onPress={() => void decide(e, true)}>
                      Accepted at the clinic
                    </Button>
                    <Button mode="outlined" icon="close" disabled={busy} onPress={() => void decide(e, false)}>
                      Declined
                    </Button>
                  </>
                )}
                {e.canBill && canBill && (
                  <Button mode="contained" icon="receipt-long" disabled={busy} onPress={() => void bill(e)}>
                    Make a bill
                  </Button>
                )}
                {e.invoiceId != null && canBill && (
                  <Button mode="outlined" icon="receipt-long" onPress={() => (close(), nav.push(`/billing/${e.invoiceId}`))}>
                    Open the bill
                  </Button>
                )}
                {e.status !== 'void' && (
                  <Button icon="block" disabled={busy} onPress={() => void voidIt(e)}>
                    Void
                  </Button>
                )}
              </View>
            </View>
          )
        }
      </AsyncView>
    </Page>
  );
}
