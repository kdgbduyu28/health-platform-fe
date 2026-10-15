import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { type ReactNode, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Button, Chip, Dialog, Divider, IconButton, Text } from 'react-native-paper';

import { ContentWidth, SplitColumns } from '../app/adaptive';
import { useClinicNav } from '../app/navigation';
import { type Invoice, type InvoiceItem, type Payment, type PaymentMethod, invoiceStatusMeta, paymentMethodMeta, wantsReference } from '../models/invoice';
import { formatPeso } from '../models/money';
import type { Service } from '../models/service';
import { invalidateBilling, useCanBill, useInvoice } from '../queries/billing';
import { useServices } from '../queries/catalog';
import { useCurrentClinicRole } from '../queries/clinical';
import { useAppRole, useRepository } from '../state/platform';
import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { ErrorView, Loading, describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { Icon } from '../ui/icon';
import { GradientBox, ListTile, MenuButton } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { BarAction, Page } from '../ui/page';
import { PaymentMethodChips, ReasonDialog, amountInput, parseAmount } from '../widgets/ledger_view';
import { usePrintStatement } from '../widgets/print_statement_sheet';

/// One bill. The front desk and admins build it while it is a draft, issue
/// it, and take payments on it; an admin can void a payment. Everyone else —
/// doctors, and the patient it is for — reads it.
///
/// Every figure on it comes back from the database after each change: the
/// screen never adds anything up itself.
export function InvoiceScreen({ invoiceId }: { invoiceId: string }) {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const invoiceAsync = useInvoice(invoiceId);
  const canBill = useCanBill().value ?? false;
  const isAdmin = useCurrentClinicRole().value === 'admin';
  const isPatient = useAppRole() === 'patient';
  const statement = usePrintStatement();
  const actions = useInvoiceActions(invoiceAsync.value ?? null);
  const back = isPatient ? '/bills' : '/billing';

  if (!invoiceAsync.hasValue) {
    return (
      <Page title="Bill" scroll={false} back={back}>
        {invoiceAsync.hasError ? <ErrorView error={invoiceAsync.error} onRetry={() => void qc.invalidateQueries({ queryKey: ['invoice'] })} /> : <Loading />}
      </Page>
    );
  }
  const v = invoiceAsync.value;
  if (v == null) {
    return (
      <Page title="Bill" back={back}>
        <Text style={{ textAlign: 'center', marginTop: 48 }}>Bill not found.</Text>
      </Page>
    );
  }
  const editing = canBill && v.isDraft;

  return (
    <Page
      title={v.number ?? 'Draft bill'}
      back={back}
      maxWidth={ContentWidth.detail}
      actions={
        <>
          {v.patient != null && v.status !== 'void' && (
            <BarAction icon="print" label="Print or save as PDF" onPress={() => statement.print(v.patient!, [v])} />
          )}
          {canBill && (v.isDraft || v.status !== 'void') && (
            <MenuButton
              items={[
                v.isDraft
                  ? { label: 'Delete draft', onPress: () => void actions.deleteDraft(back) }
                  : { label: 'Void bill', onPress: () => void actions.voidBill() },
              ]}
            />
          )}
        </>
      }
    >
      {/* A wide screen puts the bill itself on the left and what is done with
          it — notes, payments, the next step — on the right. */}
      <SplitColumns
        startFlex={3}
        endFlex={2}
        start={
          <>
            <Header invoice={v} showPatient={!isPatient} />
            <View style={{ height: 16 }} />
            <Lines invoice={v} editing={editing} actions={actions} />
            <View style={{ height: 12 }} />
            <Totals invoice={v} editing={editing} actions={actions} />
            <View style={{ height: 12 }} />
          </>
        }
        end={
          <>
            {(v.notes != null || canBill) && (
              <View style={{ marginBottom: 12 }}>
                <Card
                  title="Note on the bill"
                  action={canBill ? <Button compact onPress={() => void actions.editNotes()}>{v.notes == null ? 'Add' : 'Edit'}</Button> : undefined}
                >
                  {v.notes != null ? (
                    <Text style={{ marginTop: 4 }}>{v.notes}</Text>
                  ) : (
                    <Text style={{ fontSize: 13, color: colors.onSurfaceVariant }}>The patient sees this note too.</Text>
                  )}
                </Card>
              </View>
            )}
            {v.payments.length > 0 && (
              <View style={{ marginBottom: 12 }}>
                <Payments invoice={v} canVoid={isAdmin} actions={actions} />
              </View>
            )}
            <View style={{ height: 8 }} />
            {editing ? (
              <>
                {/* Most bills are paid on the spot: issue and pay in one. */}
                <Button mode="contained" icon="payments" disabled={v.items.length === 0} onPress={() => void actions.issueAndPay()} contentStyle={{ height: 52 }}>
                  {v.total > 0 ? `Take payment · ${formatPeso(v.total)}` : 'Take payment'}
                </Button>
                <View style={{ height: 8 }} />
                <Button mode="outlined" icon="send" disabled={v.items.length === 0} onPress={() => void actions.issue()} contentStyle={{ height: 52 }}>
                  Issue without payment
                </Button>
              </>
            ) : canBill && v.isOpen ? (
              <Button mode="contained" icon="payments" onPress={() => void actions.recordPayment()} contentStyle={{ height: 52 }}>
                Record payment · {formatPeso(v.balance)} due
              </Button>
            ) : isPatient && v.isOpen ? (
              <Text style={{ textAlign: 'center' }}>Please settle {formatPeso(v.balance)} at the clinic's front desk.</Text>
            ) : null}
            <Text style={{ marginTop: 16, textAlign: 'center', fontSize: 12, color: colors.outline }}>
              This is a statement of account, not an official receipt.
            </Text>
          </>
        }
      />
    </Page>
  );
}

function Header({ invoice: v, showPatient }: { invoice: Invoice; showPatient: boolean }) {
  const { colors } = useAppTheme();
  const on = colors.onPrimary;
  const subtitle =
    v.status === 'issued'
      ? v.amountPaid > 0
        ? `still owed of ${formatPeso(v.total)}`
        : 'due'
      : v.status === 'paid'
        ? 'paid in full'
        : v.status === 'draft'
          ? 'draft — not yet issued'
          : `void${v.voidReason == null ? '' : `: ${v.voidReason}`}`;
  return (
    <GradientBox style={{ padding: 20 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
        <Text style={{ flex: 1, fontSize: 16, fontWeight: '600', color: on }}>{showPatient && v.patient != null ? v.patient.name : v.title}</Text>
        <View style={{ paddingHorizontal: 10, paddingVertical: 4, borderRadius: 20, backgroundColor: withAlpha(on, 40 / 255) }}>
          <Text style={{ fontWeight: '600', fontSize: 12, color: on }}>{invoiceStatusMeta[v.status].label}</Text>
        </View>
      </View>
      {v.visitAt != null && (
        <Text style={{ color: withAlpha(on, 210 / 255), fontSize: 13 }}>
          {showPatient ? `${v.title} · ` : ''}
          {format(v.visitAt, 'EEE, MMM d, y')}
        </Text>
      )}
      <Text style={{ marginTop: 14, fontSize: 30, fontWeight: '700', color: on }}>{formatPeso(v.isOpen ? v.balance : v.total)}</Text>
      <Text style={{ color: withAlpha(on, 210 / 255) }}>{subtitle}</Text>
    </GradientBox>
  );
}

function Card({ title, children, action }: { title: string; children: ReactNode; action?: ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ paddingHorizontal: 16, paddingVertical: 12, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', minHeight: 32 }}>
        <Text style={{ flex: 1, fontWeight: '600', color: colors.onSurfaceVariant, fontSize: 12 }}>{title}</Text>
        {action}
      </View>
      {children}
    </View>
  );
}

function Lines({ invoice, editing, actions }: { invoice: Invoice; editing: boolean; actions: InvoiceActions }) {
  const { colors } = useAppTheme();
  return (
    <Card
      title="Items"
      action={
        editing ? (
          <Button compact icon="add" onPress={() => void actions.editLine(null)}>
            Add
          </Button>
        ) : undefined
      }
    >
      {invoice.items.length === 0 && <Text style={{ paddingVertical: 8, color: colors.onSurfaceVariant }}>Nothing on this bill yet.</Text>}
      {invoice.items.map((item) => (
        <ListTile
          key={item.id}
          dense
          paddingHorizontal={0}
          onPress={editing ? () => void actions.editLine(item) : undefined}
          title={item.description}
          subtitle={item.quantity > 1 ? `${item.quantity} × ${formatPeso(item.unitPrice)}` : undefined}
          trailing={
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <Text style={{ fontWeight: '600' }}>{formatPeso(item.amount)}</Text>
              {editing && <IconButton icon="close" size={18} accessibilityLabel="Remove" onPress={() => void actions.removeLine(item)} />}
            </View>
          }
        />
      ))}
    </Card>
  );
}

function Totals({ invoice: v, editing, actions }: { invoice: Invoice; editing: boolean; actions: InvoiceActions }) {
  const { colors } = useAppTheme();
  const row = (label: string, value: string, opts: { bold?: boolean; color?: string } = {}) => (
    <View style={{ flexDirection: 'row', paddingVertical: 3 }}>
      <Text style={{ flex: 1, color: opts.color ?? colors.onSurfaceVariant }}>{label}</Text>
      <Text style={{ color: opts.color, fontWeight: opts.bold ? '700' : '500' }}>{value}</Text>
    </View>
  );
  return (
    <Card
      title="Total"
      action={
        editing ? (
          <Button compact icon="percent" onPress={() => void actions.editDiscount()}>
            {v.discountAmount > 0 ? 'Change discount' : 'Discount'}
          </Button>
        ) : undefined
      }
    >
      <View style={{ height: 4 }} />
      {row('Subtotal', formatPeso(v.subtotal))}
      {v.discountAmount > 0 && row(`Discount${v.discountReason == null ? '' : ` (${v.discountReason})`}`, `−${formatPeso(v.discountAmount)}`)}
      <Divider style={{ marginVertical: 8 }} />
      {row('Total', formatPeso(v.total), { bold: true })}
      {v.amountPaid > 0 && row('Paid', formatPeso(v.amountPaid))}
      {v.isOpen && row('Balance', formatPeso(v.balance), { bold: true, color: colors.error })}
    </Card>
  );
}

function Payments({ invoice, canVoid, actions }: { invoice: Invoice; canVoid: boolean; actions: InvoiceActions }) {
  const { colors } = useAppTheme();
  return (
    <Card title="Payments">
      {invoice.payments.map((p) => {
        const strike = p.isVoid ? ('line-through' as const) : ('none' as const);
        return (
          <ListTile
            key={p.id}
            dense
            paddingHorizontal={0}
            leading={<Icon name={paymentMethodMeta[p.method].icon} color={p.isVoid ? colors.outline : colors.primary} />}
            title={<Text style={{ textDecorationLine: strike }}>{`${paymentMethodMeta[p.method].label}${p.reference == null ? '' : ` · ${p.reference}`}`}</Text>}
            subtitle={p.isVoid ? `Void: ${p.voidReason ?? ''}` : format(p.receivedAt, 'MMM d, y · h:mm a')}
            trailing={
              <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                <Text style={{ fontWeight: '600', textDecorationLine: strike, color: p.isVoid ? colors.outline : undefined }}>{formatPeso(p.amount)}</Text>
                {canVoid && !p.isVoid && invoice.status !== 'void' && (
                  <IconButton icon="undo" size={18} accessibilityLabel="Void payment" onPress={() => void actions.voidPayment(p)} />
                )}
              </View>
            }
          />
        );
      })}
    </Card>
  );
}

type InvoiceActions = ReturnType<typeof useInvoiceActions>;

/// Every change to the bill: ask, send, refetch, and say what went wrong in
/// the database's own words.
function useInvoiceActions(invoice: Invoice | null) {
  const repo = useRepository();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const nav = useClinicNav();
  const services = useServices().value ?? [];

  const run = async (change: () => Promise<unknown>, done?: string): Promise<boolean> => {
    try {
      await change();
      if (done != null) overlay.snack(done);
      return true;
    } catch (e) {
      overlay.snack(describeError(e));
      return false;
    } finally {
      void invalidateBilling(qc);
    }
  };

  const askText = (opts: { title: string; initial?: string | null; hint?: string; action?: string; lines?: number; allowEmpty?: boolean }) =>
    overlay.showDialog<string>((close) => <TextDialog {...opts} close={close} />);

  return {
    editLine: async (item: InvoiceItem | null) => {
      if (invoice == null) return;
      const line = await overlay.showDialog<LineDraft>((close) => <LineDialog item={item} services={services} close={close} />);
      if (line == null) return;
      await run(() =>
        item == null
          ? repo.addInvoiceItem({ invoiceId: invoice.id, clinicId: invoice.clinicId, ...line })
          : repo.updateInvoiceItem(item.id, { description: line.description, unitPrice: line.unitPrice, quantity: line.quantity }),
      );
    },
    removeLine: (item: InvoiceItem) => run(() => repo.deleteInvoiceItem(item.id)),
    editDiscount: async () => {
      if (invoice == null) return;
      const result = await overlay.showDialog<{ amount: number; reason: string }>((close) => <DiscountDialog invoice={invoice} close={close} />);
      if (result == null) return;
      await run(() => repo.setInvoiceDiscount(invoice.id, result));
    },
    editNotes: async () => {
      if (invoice == null) return;
      const text = await askText({ title: 'Note on the bill', initial: invoice.notes, hint: 'e.g. HMO: Maxicare, LOA 12345', lines: 4, allowEmpty: true });
      if (text == null) return;
      await run(() => repo.setInvoiceNotes(invoice.id, text));
    },
    issue: async () => {
      if (invoice == null) return;
      const ok = await overlay.confirm({
        title: 'Issue this bill?',
        message: `It gets a number and can no longer be edited. ${invoice.patient?.name ?? 'The patient'} will see it in their app.`,
        confirmLabel: 'Issue',
      });
      if (ok) await run(() => repo.issueInvoice(invoice.id), 'Bill issued');
    },
    /// Issues the draft and records a payment on it, once the desk has said
    /// how the patient paid. Cancelling the payment leaves it a draft.
    issueAndPay: async () => {
      if (invoice == null) return;
      const result = await overlay.showDialog<PaymentDraft>((close) => <PaymentDialog balance={invoice.total} close={close} />);
      if (result == null) return;
      await run(
        async () => {
          await repo.issueInvoice(invoice.id);
          // A bill discounted to nothing is paid the moment it is issued.
          if (invoice.total <= 0) return;
          await repo.recordPayment({ invoiceId: invoice.id, clinicId: invoice.clinicId, ...result });
        },
        result.amount >= invoice.total
          ? 'Paid in full'
          : `${formatPeso(result.amount)} received; ${formatPeso(invoice.total - result.amount)} still owed`,
      );
    },
    recordPayment: async () => {
      if (invoice == null) return;
      const result = await overlay.showDialog<PaymentDraft>((close) => <PaymentDialog balance={invoice.balance} close={close} />);
      if (result == null) return;
      await run(
        () => repo.recordPayment({ invoiceId: invoice.id, clinicId: invoice.clinicId, ...result }),
        result.amount >= invoice.balance ? 'Paid in full' : `${formatPeso(result.amount)} received`,
      );
    },
    voidPayment: async (p: Payment) => {
      const reason = await overlay.showDialog<string>((close) => (
        <ReasonDialog
          title={`Void ${formatPeso(p.amount)} ${paymentMethodMeta[p.method].label} payment?`}
          hint="Why — e.g. wrong amount, refunded"
          action="Void payment"
          close={close}
        />
      ));
      if (reason != null) await run(() => repo.voidPayment(p.id, reason), 'Payment voided');
    },
    voidBill: async () => {
      if (invoice == null) return;
      const reason = await overlay.showDialog<string>((close) => (
        <ReasonDialog title={`Void ${invoice.label}?`} hint="Why — e.g. billed the wrong patient" action="Void bill" close={close} />
      ));
      if (reason != null) await run(() => repo.voidInvoice(invoice.id, reason), 'Bill voided');
    },
    deleteDraft: async (fallback: string) => {
      if (invoice == null) return;
      const ok = await overlay.confirm({ title: 'Delete this draft?', message: 'It was never issued.', confirmLabel: 'Delete' });
      if (!ok) return;
      if (await run(() => repo.deleteInvoice(invoice.id))) nav.back(fallback);
    },
  };
}

/// Asks for one line of text. Nothing if cancelled; with [allowEmpty], an
/// empty string means "clear it".
function TextDialog({
  title,
  initial,
  hint,
  action = 'Save',
  lines = 1,
  allowEmpty = false,
  close,
}: {
  title: string;
  initial?: string | null;
  hint?: string;
  action?: string;
  lines?: number;
  allowEmpty?: boolean;
  close: Close<string>;
}) {
  const [text, setText] = useState(initial ?? '');
  const ok = allowEmpty || text.trim() !== '';
  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.Content>
        <TextField autoFocus multiline={lines > 1} minLines={lines} placeholder={hint} value={text} onChangeText={setText} />
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={!ok} onPress={() => close(text.trim())}>
          {action}
        </Button>
      </Dialog.Actions>
    </>
  );
}

type LineDraft = { description: string; unitPrice: number; quantity: number; serviceId: string | null };

function LineDialog({ item, services, close }: { item: InvoiceItem | null; services: Service[]; close: Close<LineDraft> }) {
  const [description, setDescription] = useState(item?.description ?? '');
  const [price, setPrice] = useState(item == null ? '' : item.unitPrice.toFixed(2));
  const [quantity, setQuantity] = useState(`${item?.quantity ?? 1}`);
  const [serviceId, setServiceId] = useState<string | null>(null);
  const p = parseAmount(price);
  const q = /^\d+$/.test(quantity) ? Number(quantity) : null;
  const valid = description.trim() !== '' && p != null && p >= 0 && q != null && q >= 1 && q <= 999;
  return (
    <>
      <Dialog.Title>{item == null ? 'Add item' : 'Edit item'}</Dialog.Title>
      <Dialog.ScrollArea style={{ maxHeight: 520 }}>
        <ScrollView contentContainerStyle={{ paddingVertical: 8, gap: 12 }}>
          {item == null && services.length > 0 && (
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
              {services.map((s) => (
                <Chip
                  key={s.id}
                  compact
                  mode="outlined"
                  onPress={() => {
                    setServiceId(s.id);
                    setDescription(s.name);
                    setPrice((s.price ?? 0).toFixed(2));
                  }}
                >
                  {s.priceLabel == null ? s.name : `${s.name} · ${s.priceLabel}`}
                </Chip>
              ))}
            </View>
          )}
          <TextField
            label="Description"
            autoFocus={item != null}
            value={description}
            onChangeText={(t) => {
              setDescription(t);
              setServiceId(null);
            }}
          />
          <View style={{ flexDirection: 'row', gap: 12 }}>
            <TextField style={{ flex: 2 }} label="Price" prefix="₱" keyboardType="decimal-pad" value={price} onChangeText={(t) => setPrice(amountInput(t))} />
            <TextField style={{ flex: 1 }} label="Qty" keyboardType="number-pad" value={quantity} onChangeText={(t) => setQuantity(t.replace(/\D/g, ''))} />
          </View>
        </ScrollView>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={!valid} onPress={() => close({ description: description.trim(), unitPrice: p!, quantity: q!, serviceId })}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}

function DiscountDialog({ invoice, close }: { invoice: Invoice; close: Close<{ amount: number; reason: string }> }) {
  const [amount, setAmount] = useState(invoice.discountAmount > 0 ? invoice.discountAmount.toFixed(2) : '');
  const [reason, setReason] = useState(invoice.discountReason ?? '');
  const parsed = amount.trim() === '' ? 0 : parseAmount(amount);
  const valid = parsed != null && parsed >= 0 && parsed <= invoice.subtotal;
  const twentyPercent = (why: string) => {
    setAmount((Math.round(invoice.subtotal * 0.2 * 100) / 100).toFixed(2));
    setReason(why);
  };
  return (
    <>
      <Dialog.Title>Discount</Dialog.Title>
      <Dialog.Content style={{ gap: 12 }}>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 6 }}>
          <Chip compact mode="outlined" onPress={() => twentyPercent('Senior citizen')}>
            Senior citizen 20%
          </Chip>
          <Chip compact mode="outlined" onPress={() => twentyPercent('PWD')}>
            PWD 20%
          </Chip>
        </View>
        <TextField
          label="Amount off"
          prefix="₱"
          keyboardType="decimal-pad"
          helperText={`Of ${formatPeso(invoice.subtotal)}. Empty or 0 removes it.`}
          value={amount}
          onChangeText={(t) => setAmount(amountInput(t))}
        />
        <TextField label="Reason (shown on the bill)" value={reason} onChangeText={setReason} />
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button mode="contained" disabled={!valid} onPress={() => close({ amount: parsed!, reason: reason.trim() })}>
          Save
        </Button>
      </Dialog.Actions>
    </>
  );
}

type PaymentDraft = { amount: number; method: PaymentMethod; reference: string | null };

function PaymentDialog({ balance, close }: { balance: number; close: Close<PaymentDraft> }) {
  const { colors } = useAppTheme();
  const [amount, setAmount] = useState(balance.toFixed(2));
  const [reference, setReference] = useState('');
  const [method, setMethod] = useState<PaymentMethod>('cash');
  const [allMethods, setAllMethods] = useState(false);
  const parsed = parseAmount(amount);
  const valid = parsed != null && parsed > 0 && parsed <= balance + 0.001;
  const referenceLabel = method === 'hmo' ? 'Approval / LOA code' : method === 'card' ? 'Approval code' : 'Reference number';
  return (
    <>
      <Dialog.Title>Record payment</Dialog.Title>
      <Dialog.ScrollArea style={{ maxHeight: 520 }}>
        <ScrollView contentContainerStyle={{ paddingVertical: 8, gap: 12 }}>
          <Text style={{ fontSize: 12, color: colors.onSurfaceVariant }}>How did they pay?</Text>
          <PaymentMethodChips value={method} onChange={setMethod} showAll={allMethods} onShowAll={() => setAllMethods(true)} />
          <TextField
            label="Amount received"
            prefix="₱"
            keyboardType="decimal-pad"
            helperText={`${formatPeso(balance)} due`}
            value={amount}
            onChangeText={(t) => setAmount(amountInput(t))}
          />
          {wantsReference(method) && <TextField label={referenceLabel} value={reference} onChangeText={setReference} />}
        </ScrollView>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
        <Button
          mode="contained"
          disabled={!valid}
          onPress={() => close({ amount: parsed!, method, reference: wantsReference(method) ? reference.trim() : null })}
        >
          Record
        </Button>
      </Dialog.Actions>
    </>
  );
}
