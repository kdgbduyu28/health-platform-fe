import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { FlatList, Pressable, ScrollView, View } from 'react-native';
import { Button, Chip, Dialog, FAB, Text } from 'react-native-paper';

import { Breakpoints, ContentWidth, useLayoutWidth } from '../app/adaptive';
import { type Invoice, invoiceStatusMeta } from '../models/invoice';
import { formatPeso } from '../models/money';
import type { Patient } from '../models/patient';
import { invalidateBilling, useBillingSummary, useCanBill, useClinicInvoices } from '../queries/billing';
import { usePatientSearch } from '../queries/catalog';
import { useCurrentClinicId } from '../queries/clinic';
import { useRepository } from '../state/platform';
import { useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { AsyncView, describeError } from '../ui/async_view';
import { TextField } from '../ui/fields';
import { ListTile, Tabs } from '../ui/kit';
import { type Close, useOverlay } from '../ui/overlay';
import { BarAction, Page } from '../ui/page';
import { startOfDay } from '../util/dates';
import { InvoiceStatusChip, InvoiceTile } from '../widgets/billing_widgets';
import { AccountMenuButton, ClinicTitle, NotificationsButton } from '../widgets/chrome';
import { LedgerView } from '../widgets/ledger_view';

type Filter = 'unpaid' | 'drafts' | 'paid' | 'all';
const filterLabel: Record<Filter, string> = { unpaid: 'Unpaid', drafts: 'Drafts', paid: 'Paid', all: 'All' };

/// The clinic's bills and its ledger, for the front desk and admins.
///
/// Bills: what came in today, what is still owed, and every bill by state.
/// Ledger: gross, paid, pending, expenses and net over some days.
///
/// [onOpenInvoice] is how the app opens a bill and [onOpenPrices] its price
/// list.
export function BillingScreen({ onOpenInvoice, onOpenPrices }: { onOpenInvoice: (id: string) => void; onOpenPrices?: () => void }) {
  const canBill = useCanBill().value ?? false;
  const [tab, setTab] = useState<'bills' | 'ledger'>('bills');
  return (
    <Page
      title={<ClinicTitle page="Billing" />}
      scroll={false}
      actions={
        <>
          {canBill && onOpenPrices && <BarAction icon="sell" label="Prices" onPress={onOpenPrices} />}
          <NotificationsButton />
          <AccountMenuButton />
        </>
      }
      belowAppBar={
        canBill ? (
          <Tabs
            value={tab}
            onChange={setTab}
            tabs={[
              { value: 'bills', label: 'Bills' },
              { value: 'ledger', label: 'Ledger' },
            ]}
          />
        ) : undefined
      }
    >
      {canBill && tab === 'ledger' ? <LedgerView onOpenInvoice={onOpenInvoice} /> : <Bills canBill={canBill} onOpenInvoice={onOpenInvoice} />}
    </Page>
  );
}

function Bills({ canBill, onOpenInvoice }: { canBill: boolean; onOpenInvoice: (id: string) => void }) {
  const { colors } = useAppTheme();
  const readable = useReadable();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const repo = useRepository();
  const clinicId = useCurrentClinicId();
  const invoices = useClinicInvoices();
  const today = startOfDay(new Date());
  const summary = useBillingSummary({ from: today, to: today }).value ?? null;
  const [filter, setFilter] = useState<Filter>('unpaid');
  const [query, setQuery] = useState('');
  const [width, onLayout] = useLayoutWidth();
  // Columns once there is room: patient, what for, number, date, total,
  // balance and state line up to scan down.
  const wide = width >= Breakpoints.twoPane;
  const maxWidth = (wide ? ContentWidth.wide : ContentWidth.list) + 32;

  /// A bill not tied to a visit — a retainer, a product. Most bills start
  /// from the visit instead.
  const newBill = async () => {
    const patient = await overlay.showDialog<Patient>((close) => <PatientPicker close={close} />);
    if (patient == null || clinicId == null) return;
    try {
      const id = await repo.createInvoice({ clinicId, patientId: patient.id });
      void invalidateBilling(qc);
      onOpenInvoice(id);
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  const shown = (all: Invoice[]) =>
    all.filter((v) => {
      const inFilter =
        filter === 'unpaid' ? v.status === 'issued' : filter === 'drafts' ? v.status === 'draft' : filter === 'paid' ? v.status === 'paid' : true;
      if (!inFilter) return false;
      if (query === '') return true;
      return (v.patient?.name.toLowerCase().includes(query) ?? false) || (v.number?.toLowerCase().includes(query) ?? false);
    });

  const paidColor = readable(invoiceStatusMeta.paid.color);
  const owedColor = readable(invoiceStatusMeta.issued.color);

  const header = (
    <View style={{ width: '100%', maxWidth, alignSelf: 'center' }}>
      <View style={{ flexDirection: 'row', gap: 8, paddingHorizontal: 16, paddingTop: 8 }}>
        <Stat label="Collected today" value={summary == null ? '—' : formatPeso(summary.collected)} color={paidColor} />
        <Stat
          label={summary == null ? 'Owed' : `Owed on ${summary.unpaidCount} ${summary.unpaidCount === 1 ? 'bill' : 'bills'}`}
          value={summary == null ? '—' : formatPeso(summary.outstanding)}
          color={owedColor}
        />
      </View>
      <TextField
        style={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 4 }}
        icon="search"
        placeholder="Search by patient or bill number…"
        value={query}
        onChangeText={(v) => setQuery(v.trim().toLowerCase())}
      />
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 8, gap: 8 }}>
        {(Object.keys(filterLabel) as Filter[]).map((f) => (
          <Chip key={f} mode="outlined" selected={filter === f} showSelectedCheck onPress={() => setFilter(f)}>
            {filterLabel[f]}
          </Chip>
        ))}
      </ScrollView>
    </View>
  );

  return (
    <View style={{ flex: 1 }} onLayout={onLayout}>
      <AsyncView value={invoices} onRetry={() => void qc.invalidateQueries({ queryKey: ['invoices'] })}>
        {(all) => {
          const list = shown(all);
          return (
            <FlatList
              data={list}
              keyExtractor={(v) => v.id}
              ListHeaderComponent={
                <>
                  {header}
                  {wide && list.length > 0 && <BillRowHeading maxWidth={maxWidth} />}
                </>
              }
              ListEmptyComponent={
                <Text variant="titleMedium" style={{ textAlign: 'center', paddingTop: 48 }}>
                  {query !== '' ? `No bills match "${query}"` : 'Nothing here'}
                </Text>
              }
              contentContainerStyle={{ paddingBottom: 88 }}
              renderItem={({ item, index }) => (
                <View style={{ width: '100%', maxWidth, alignSelf: 'center', paddingHorizontal: wide ? 0 : 12 }}>
                  {wide ? (
                    <BillRow invoice={item} last={index === list.length - 1} onPress={() => onOpenInvoice(item.id)} />
                  ) : (
                    <InvoiceTile invoice={item} showPatient onPress={() => onOpenInvoice(item.id)} />
                  )}
                </View>
              )}
            />
          );
        }}
      </AsyncView>
      {canBill && <FAB icon="add" label="New bill" onPress={() => void newBill()} style={{ position: 'absolute', right: 16, bottom: 16 }} />}
    </View>
  );
}

// ── Bills as a table (tablet and up) ────────────────────────────────────────

const billFlex = [4, 4, 3, 3, 3, 3];
const statusWidth = 104;

function BillCells({ cells }: { cells: React.ReactNode[] }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center' }}>
      {cells.map((c, i) =>
        i < billFlex.length ? (
          <View key={i} style={{ flex: billFlex[i], minWidth: 0 }}>
            {c}
          </View>
        ) : (
          <View key={i} style={{ width: statusWidth }}>
            {c}
          </View>
        ),
      )}
    </View>
  );
}

function BillRowHeading({ maxWidth }: { maxWidth: number }) {
  const { colors } = useAppTheme();
  const h = (t: string, end = false) => (
    <Text variant="labelMedium" style={{ fontWeight: '700', color: colors.onSurfaceVariant, textAlign: end ? 'right' : 'left' }}>
      {t}
    </Text>
  );
  return (
    <View style={{ width: '100%', maxWidth, alignSelf: 'center' }}>
      <View
        style={{
          marginHorizontal: 16,
          marginTop: 4,
          padding: 12,
          paddingHorizontal: 16,
          borderTopLeftRadius: 16,
          borderTopRightRadius: 16,
          backgroundColor: colors.surfaceContainerHighest,
        }}
      >
        <BillCells cells={[h('Patient'), h('For'), h('Bill'), h('Date'), h('Total', true), h('Balance', true), <View style={{ paddingLeft: 16 }}>{h('State')}</View>]} />
      </View>
    </View>
  );
}

function BillRow({ invoice: v, onPress, last }: { invoice: Invoice; onPress: () => void; last: boolean }) {
  const { colors } = useAppTheme();
  const when = v.visitAt ?? v.issuedAt ?? v.createdAt;
  const muted = { color: colors.onSurfaceVariant };
  return (
    <Pressable
      onPress={onPress}
      style={({ hovered }) => ({
        marginHorizontal: 16,
        paddingHorizontal: 16,
        paddingVertical: 14,
        backgroundColor: hovered ? colors.surfaceContainer : colors.surfaceContainerLow,
        borderBottomLeftRadius: last ? 16 : 0,
        borderBottomRightRadius: last ? 16 : 0,
        borderBottomWidth: last ? 0 : 1,
        borderBottomColor: withAlpha(colors.outlineVariant, 120 / 255),
      })}
    >
      <BillCells
        cells={[
          <Text numberOfLines={1} style={{ fontWeight: '600' }}>
            {v.patient?.name ?? '—'}
          </Text>,
          <Text numberOfLines={1}>{v.title}</Text>,
          <Text style={muted}>{v.label}</Text>,
          <Text style={muted}>{format(when, 'MMM d, y')}</Text>,
          <Text style={{ textAlign: 'right', fontWeight: '600' }}>{formatPeso(v.total)}</Text>,
          <Text style={[{ textAlign: 'right' }, v.isOpen ? { color: colors.error, fontWeight: '600' } : muted]}>{v.isOpen ? formatPeso(v.balance) : '—'}</Text>,
          <View style={{ paddingLeft: 16, alignItems: 'flex-start' }}>
            <InvoiceStatusChip status={v.status} />
          </View>,
        ]}
      />
    </Pressable>
  );
}

function Stat({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <View style={{ flex: 1, padding: 12, borderRadius: 14, backgroundColor: withAlpha(color, 22 / 255), borderWidth: 1, borderColor: withAlpha(color, 60 / 255) }}>
      <Text style={{ fontSize: 20, fontWeight: '700', color }}>{value}</Text>
      <Text style={{ fontSize: 12, color }}>{label}</Text>
    </View>
  );
}

function PatientPicker({ close }: { close: Close<Patient> }) {
  const qc = useQueryClient();
  const [query, setQuery] = useState('');
  const search = usePatientSearch(query);
  return (
    <>
      <Dialog.Title>Bill which patient?</Dialog.Title>
      <Dialog.Content style={{ height: 420 }}>
        <TextField autoFocus icon="search" placeholder="Name or phone" value={query} onChangeText={(v) => setQuery(v.trim().toLowerCase())} />
        <View style={{ height: 8 }} />
        {/* Searched in the database; the first few matches only. */}
        <View style={{ flex: 1 }}>
          <AsyncView value={search} onRetry={() => void qc.invalidateQueries({ queryKey: ['patientSearch'] })}>
            {(shown) => (
              <ScrollView>
                {shown.map((p) => (
                  <ListTile key={p.id} title={p.name} subtitle={p.phone} onPress={() => close(p)} />
                ))}
              </ScrollView>
            )}
          </AsyncView>
        </View>
      </Dialog.Content>
      <Dialog.Actions>
        <Button onPress={() => close()}>Cancel</Button>
      </Dialog.Actions>
    </>
  );
}
