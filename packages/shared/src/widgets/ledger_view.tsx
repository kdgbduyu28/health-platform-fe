import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Button, Chip, Dialog, ProgressBar, Text } from 'react-native-paper';

import { ContentWidth, useLayoutWidth } from '../app/adaptive';
import { commonPaymentMethods, invoiceStatusMeta, type PaymentMethod, paymentMethodMeta, paymentMethods, wantsReference } from '../models/invoice';
import { expenseCategories, type LedgerEntry, type LedgerSummary } from '../models/ledger';
import { formatPeso } from '../models/money';
import { type BillingRange, invalidateBilling, useLedgerEntries, useLedgerSummary } from '../queries/billing';
import { useCurrentClinicId } from '../queries/clinic';
import { useCurrentClinicRole } from '../queries/clinical';
import { useRepository } from '../state/platform';
import { useAppTheme, useReadable } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { DateField, TextField, useDatePicker } from '../ui/fields';
import { Icon, type IconName } from '../ui/icon';
import { Avatar, ListTile } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { addDays, isSameDay, isoWeekday, startOfDay } from '../util/dates';

type Period = 'today' | 'week' | 'month' | 'custom';
const periodLabel: Record<Period, string> = { today: 'Today', week: 'This week', month: 'This month', custom: 'Pick dates…' };

/// A typed amount: commas and the peso sign allowed, nothing else.
export function parseAmount(text: string): number | null {
  const cleaned = text.replace(/,/g, '').replace(/₱/g, '').trim();
  if (cleaned === '' || !/^\d*\.?\d*$/.test(cleaned)) return null;
  const n = Number(cleaned);
  return Number.isNaN(n) ? null : n;
}

/// Keeps only what an amount may contain while it is typed.
export function amountInput(text: string): string {
  return text.replace(/[^0-9.,]/g, '');
}

/// The clinic's money over some days: gross, paid, pending, expenses and
/// net, how it was paid, and every payment in and expense out behind them.
/// For the front desk and admins — the database refuses anyone else.
///
/// Every figure is the database's (`ledger_summary`); nothing is added up
/// here.
export function LedgerView({ onOpenInvoice }: { onOpenInvoice: (invoiceId: string) => void }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const role = useCurrentClinicRole().value;
  const [period, setPeriod] = useState<Period>('today');
  const [custom, setCustom] = useState<BillingRange | null>(null);

  const today = startOfDay(new Date());
  const range: BillingRange =
    period === 'today'
      ? { from: today, to: today }
      : period === 'week'
        ? // Monday to today.
          { from: addDays(today, -(isoWeekday(today) - 1)), to: today }
        : period === 'month'
          ? { from: new Date(today.getFullYear(), today.getMonth(), 1), to: today }
          : { from: custom?.from ?? today, to: custom?.to ?? today };
  const summary = useLedgerSummary(range);
  const entries = useLedgerEntries(range);
  const label = isSameDay(range.from, range.to)
    ? format(range.from, 'MMM d, y')
    : `${format(range.from, 'MMM d, y')} – ${format(range.to, 'MMM d, y')}`;

  const pickRange = async () => {
    const picked = await overlay.showDialog<BillingRange>((close) => (
      <RangeDialog initial={custom ?? range} first={new Date(today.getFullYear() - 5, 0, 1)} last={today} close={close} />
    ));
    if (picked) {
      setCustom(picked);
      setPeriod('custom');
    }
  };

  const addExpense = async () => {
    if (clinicId == null) return;
    const saved = await overlay.showDialog<boolean>((close) => <ExpenseDialog clinicId={clinicId} close={close} />);
    if (saved) void invalidateBilling(qc);
  };

  /// An admin may void an expense; everyone else just sees it.
  const expenseMenu = async (e: LedgerEntry) => {
    if (role !== 'admin' || e.voided) return;
    const reason = await overlay.showDialog<string>((close) => (
      <ReasonDialog title={`Void ${formatPeso(e.amount)} ${e.title} expense?`} hint="Why — e.g. entered twice" action="Void expense" close={close} />
    ));
    if (reason == null) return;
    try {
      await repo.voidExpense(e.id, reason);
      overlay.snack('Expense voided');
    } catch (err) {
      overlay.snack(describeError(err));
    } finally {
      void invalidateBilling(qc);
    }
  };

  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 96, width: '100%', maxWidth: ContentWidth.detail, alignSelf: 'center' }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
        {(Object.keys(periodLabel) as Period[]).map((p) => (
          <Chip key={p} mode="outlined" selected={period === p} showSelectedCheck onPress={() => (p === 'custom' ? void pickRange() : setPeriod(p))}>
            {periodLabel[p]}
          </Chip>
        ))}
      </ScrollView>
      <Text style={{ paddingVertical: 8, color: colors.onSurfaceVariant }}>{label}</Text>
      <AsyncView value={summary} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['ledgerSummary'] })}>
        {(s) => (s == null ? null : <Summary s={s} />)}
      </AsyncView>
      <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 16, marginBottom: 8 }}>
        <Text variant="titleMedium" style={{ flex: 1 }}>
          Money in and out
        </Text>
        <Button mode="contained-tonal" icon="remove-circle-outline" onPress={addExpense}>
          Add expense
        </Button>
      </View>
      <AsyncView value={entries} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['ledgerEntries'] })}>
        {(list) =>
          list.length === 0 ? (
            <Text style={{ paddingVertical: 24, textAlign: 'center' }}>Nothing in these days.</Text>
          ) : (
            <View>
              {list.map((e) => (
                <EntryTile
                  key={`${e.kind}${e.id}`}
                  entry={e}
                  onPress={e.isExpense ? () => void expenseMenu(e) : e.invoiceId == null ? undefined : () => onOpenInvoice(e.invoiceId!)}
                />
              ))}
            </View>
          )
        }
      </AsyncView>
    </ScrollView>
  );
}

function RangeDialog({ initial, first, last, close }: { initial: BillingRange; first: Date; last: Date; close: Close<BillingRange> }) {
  const [from, setFrom] = useState<Date | null>(initial.from);
  const [to, setTo] = useState<Date | null>(initial.to);
  const valid = from != null && to != null && from.getTime() <= to.getTime();
  return (
    <>
      <Dialog.Title>Pick dates</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <DateField label="From" value={from} onChange={setFrom} min={first} max={to ?? last} />
        <DateField label="To" value={to} onChange={setTo} min={from ?? first} max={last} />
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={!valid} onPress={() => close({ from: from!, to: to! })}>
          OK
        </Button>
      </Dialog.Actions>
    </>
  );
}

function plural(n: number, one: string): string {
  return `${n} ${one}${n === 1 ? '' : 's'}`;
}

function Summary({ s }: { s: LedgerSummary }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const [width, onLayout] = useLayoutWidth();
  const paid = readable(invoiceStatusMeta.paid.color);
  const owed = readable(invoiceStatusMeta.issued.color);
  const red = readable(invoiceStatusMeta.void.color);
  const tiles: TileProps[] = [
    {
      label: 'Gross',
      value: s.gross,
      icon: 'receipt-long',
      accent: colors.primary,
      note: s.discounts > 0 ? `${plural(s.billCount, 'bill')} · ${formatPeso(s.discounts)} off` : plural(s.billCount, 'bill'),
    },
    { label: 'Paid', value: s.paid, icon: 'check-circle-outline', accent: paid, note: plural(s.paymentCount, 'payment') },
    { label: 'Pending', value: s.pending, icon: 'hourglass-bottom', accent: owed, note: "on these days' bills" },
    { label: 'Expenses', value: s.expenses, icon: 'remove-circle-outline', accent: red },
    { label: 'Net', value: s.net, icon: s.net >= 0 ? 'trending-up' : 'trending-down', accent: s.net >= 0 ? paid : red, note: 'paid − expenses', emphasis: true },
  ];
  const columns = width >= 720 ? 5 : width >= 420 ? 3 : 2;
  const gap = 8;
  const tileWidth = (width - gap * (columns - 1)) / columns;
  return (
    <View onLayout={onLayout}>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap }}>
        {tiles.map((t) => (
          <View key={t.label} style={{ width: tileWidth }}>
            <Tile {...t} />
          </View>
        ))}
      </View>
      {(s.outstanding > 0 || s.draftCount > 0) && (
        <Text style={{ marginTop: 8, fontSize: 12, color: colors.onSurfaceVariant }}>
          {[
            ...(s.outstanding > 0 ? [`Owed overall: ${formatPeso(s.outstanding)} on ${plural(s.unpaidCount, 'bill')}`] : []),
            ...(s.draftCount > 0 ? [`${plural(s.draftCount, 'draft')} not issued yet (${formatPeso(s.draftTotal)})`] : []),
          ].join(' · ')}
        </Text>
      )}
      {s.byMethod.size > 0 && (
        <View style={{ marginTop: 16 }}>
          <Breakdown
            title="Paid by"
            rows={paymentMethods.filter((m) => s.byMethod.has(m)).map((m) => [paymentMethodMeta[m].label, s.byMethod.get(m)!] as [string, number])}
            color={paid}
          />
        </View>
      )}
      {s.byCategory.size > 0 && (
        <View style={{ marginTop: 12 }}>
          <Breakdown title="Spent on" rows={[...s.byCategory.entries()].sort((a, b) => b[1] - a[1])} color={red} />
        </View>
      )}
    </View>
  );
}

type TileProps = { label: string; value: number; icon: IconName; accent: string; note?: string; emphasis?: boolean };

function Tile({ label, value, icon, accent, note, emphasis = false }: TileProps) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        padding: 12,
        borderRadius: 14,
        borderLeftWidth: 4,
        borderLeftColor: accent,
        backgroundColor: emphasis ? colors.surfaceContainerHigh : colors.surfaceContainerLow,
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name={icon} size={16} color={accent} />
        <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant }}>{label}</Text>
      </View>
      <Text numberOfLines={1} adjustsFontSizeToFit style={{ marginTop: 6, fontSize: 20, fontWeight: '700' }}>
        {formatPeso(value)}
      </Text>
      {note != null && (
        <Text numberOfLines={1} style={{ fontSize: 11, color: colors.onSurfaceVariant }}>
          {note}
        </Text>
      )}
    </View>
  );
}

/// Each row's share of the total as a thin bar, one colour, the amount in
/// text beside it.
function Breakdown({ title, rows, color }: { title: string; rows: [string, number][]; color: string }) {
  const { colors } = useAppTheme();
  const top = rows.reduce((m, [, v]) => (v > m ? v : m), 0);
  return (
    <View style={{ padding: 12, borderRadius: 14, backgroundColor: colors.surfaceContainerLow }}>
      <Text style={{ fontSize: 12, fontWeight: '600', color: colors.onSurfaceVariant, marginBottom: 8 }}>{title}</Text>
      {rows.map(([name, value]) => (
        <View key={name} style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 4 }}>
          <Text numberOfLines={1} style={{ width: 96 }}>
            {name}
          </Text>
          <View style={{ flex: 1, borderRadius: 4, overflow: 'hidden' }}>
            <ProgressBar progress={top === 0 ? 0 : value / top} color={color} style={{ height: 8, backgroundColor: colors.surfaceContainerHighest }} />
          </View>
          <Text style={{ width: 108, textAlign: 'right', fontWeight: '600' }}>{formatPeso(value)}</Text>
        </View>
      ))}
    </View>
  );
}

function EntryTile({ entry: e, onPress }: { entry: LedgerEntry; onPress?: () => void }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const strike = e.voided ? ('line-through' as const) : ('none' as const);
  const when = e.isExpense ? format(e.at, 'MMM d') : format(e.at, 'MMM d · h:mm a');
  return (
    <ListTile
      paddingHorizontal={0}
      onPress={onPress}
      leading={
        <Avatar
          icon={e.isExpense ? 'arrow-upward' : 'arrow-downward'}
          color={colors.surfaceContainerHigh}
          textColor={e.voided ? colors.outline : readable(e.isExpense ? invoiceStatusMeta.void.color : invoiceStatusMeta.paid.color)}
        />
      }
      title={<Text style={{ textDecorationLine: strike }}>{e.title}</Text>}
      subtitle={
        <Text numberOfLines={2} style={{ color: colors.onSurfaceVariant }}>
          {e.voided
            ? `Void: ${e.voidReason ?? ''}`
            : [when, paymentMethodMeta[e.method].label, ...(e.detail != null ? [e.detail] : []), ...(e.reference != null ? [e.reference] : [])].join(' · ')}
        </Text>
      }
      trailing={
        <Text style={{ fontWeight: '600', textDecorationLine: strike, color: e.voided ? colors.outline : colors.onSurface }}>
          {`${e.isExpense ? '−' : '+'}${formatPeso(e.amount)}`}
        </Text>
      }
    />
  );
}

function ExpenseDialog({ clinicId, close }: { clinicId: string; close: Close<boolean> }) {
  const { colors } = useAppTheme();
  const repo = useRepository();
  const pickDate = useDatePicker();
  const [amount, setAmount] = useState('');
  const [category, setCategory] = useState('');
  const [description, setDescription] = useState('');
  const [reference, setReference] = useState('');
  const [method, setMethod] = useState<PaymentMethod>('cash');
  const [day, setDay] = useState(() => startOfDay(new Date()));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const parsed = parseAmount(amount);
  const valid = (parsed ?? 0) > 0 && category.trim() !== '' && !busy;

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await repo.addExpense({
        clinicId,
        spentOn: day,
        category: category.trim(),
        amount: parsed!,
        method,
        description: description.trim(),
        reference: wantsReference(method) ? reference.trim() : null,
      });
      close(true);
    } catch (e) {
      setBusy(false);
      setError(describeError(e));
    }
  };

  return (
    <>
      <Dialog.Title>Add expense</Dialog.Title>
      <Dialog.ScrollArea style={{ maxHeight: 520 }}>
        <ScrollView contentContainerStyle={{ paddingVertical: 8, gap: 12 }}>
          <TextField label="Amount" prefix="₱" autoFocus keyboardType="decimal-pad" value={amount} onChangeText={(t) => setAmount(amountInput(t))} />
          <TextField label="Category" autoCapitalize="sentences" value={category} onChangeText={setCategory} />
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
            {expenseCategories.map((c) => (
              <Chip key={c} compact mode="outlined" selected={category.trim() === c} onPress={() => setCategory(c)}>
                {c}
              </Chip>
            ))}
          </View>
          <TextField label="What for (optional)" placeholder="e.g. Gloves and masks, 5 boxes" value={description} onChangeText={setDescription} />
          <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>Paid with</Text>
          <MethodPicker value={method} onChange={setMethod} />
          {wantsReference(method) && <TextField label="Reference (optional)" value={reference} onChangeText={setReference} />}
          <Button
            mode="outlined"
            icon="event"
            onPress={async () => {
              const today = startOfDay(new Date());
              const picked = await pickDate({ initial: day, first: new Date(today.getFullYear() - 2, 0, 1), last: today });
              if (picked) setDay(picked);
            }}
          >
            Spent on {format(day, 'EEE, MMM d, y')}
          </Button>
          {error != null && <Text style={{ color: colors.error }}>{error}</Text>}
        </ScrollView>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button disabled={busy} onPress={() => close(false)}>
          Cancel
        </Button>
        <Button mode="contained" disabled={!valid} onPress={save}>
          Add
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// Asks why, for a void: answers the reason, or nothing if cancelled.
export function ReasonDialog({ title, hint, action, close, message }: { title: string; hint: string; action: string; close: Close<string>; message?: string }) {
  const [reason, setReason] = useState('');
  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        {message != null && <Text>{message}</Text>}
        <TextField autoFocus placeholder={hint} value={reason} onChangeText={setReason} onSubmit={() => reason.trim() !== '' && close(reason.trim())} />
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={reason.trim() === ''} onPress={() => close(reason.trim())}>
          {action}
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// The common methods as chips, the rest behind "More".
function MethodPicker({ value, onChange }: { value: PaymentMethod; onChange: (m: PaymentMethod) => void }) {
  const [all, setAll] = useState(!commonPaymentMethods.includes(value));
  return <PaymentMethodChips value={value} onChange={onChange} showAll={all} onShowAll={() => setAll(true)} />;
}

/// Payment method chips: the common ones first, the rest once [showAll].
/// Shared by the payment and expense dialogs.
export function PaymentMethodChips({
  value,
  onChange,
  showAll,
  onShowAll,
}: {
  value: PaymentMethod;
  onChange: (m: PaymentMethod) => void;
  showAll: boolean;
  onShowAll: () => void;
}) {
  const methods = showAll ? paymentMethods : commonPaymentMethods;
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
      {methods.map((m) => (
        <Chip key={m} mode="outlined" selected={m === value} icon={paymentMethodMeta[m].icon} onPress={() => onChange(m)}>
          {paymentMethodMeta[m].label}
        </Chip>
      ))}
      {!showAll && (
        <Chip mode="outlined" icon="expand-more" onPress={onShowAll}>
          More
        </Chip>
      )}
    </View>
  );
}
