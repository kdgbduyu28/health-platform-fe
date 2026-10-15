import { format } from 'date-fns';
import { useState } from 'react';
import { View } from 'react-native';
import { Button, Checkbox, Divider, Text } from 'react-native-paper';

import { buildStatementHtml } from '../billing/statement';
import type { Invoice } from '../models/invoice';
import { formatPeso } from '../models/money';
import type { Patient } from '../models/patient';
import { printHtml } from '../platform/browser';
import { useCurrentClinic } from '../queries/clinic';
import { clinicImageUrl } from '../theme/brand';
import { useAppTheme } from '../theme/clinic_theme';
import { ListTile } from '../ui/kit';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { InvoiceStatusChip } from './billing_widgets';

/// Opening the print dialog on a statement of a patient's bills.
export function usePrintStatement() {
  const clinic = useCurrentClinic().value ?? null;
  const overlay = useOverlay();

  /// Opens the print dialog on a statement of [invoices] straight away. For
  /// a bill's own page, where there is nothing to choose.
  const print = (patient: Patient, invoices: Invoice[]) => {
    if (clinic == null) return;
    const opened = printHtml(buildStatementHtml({ clinic, patient, invoices, logoSrc: clinicImageUrl }));
    if (!opened) overlay.snack('Printing works in the web app.');
  };

  return {
    print,
    /// Asks which of [patient]'s bills — one per visit — to put on a
    /// statement, then opens the print dialog on it, to print or save as a
    /// PDF.
    ///
    /// [invoices] newest first, as the patient's bills come. Voided bills are
    /// not offered. The newest bill starts ticked, since the usual ask is a
    /// receipt for the visit just finished.
    choose: (patient: Patient, invoices: Invoice[]) =>
      void overlay.showSheet((close) => <PrintStatementSheet patient={patient} invoices={invoices} onPrint={print} close={close} />),
  };
}

function PrintStatementSheet({
  patient,
  invoices,
  onPrint,
  close,
}: {
  patient: Patient;
  invoices: Invoice[];
  onPrint: (patient: Patient, invoices: Invoice[]) => void;
  close: Close<void>;
}) {
  const { colors } = useAppTheme();
  const [bills] = useState(() => invoices.filter((v) => v.status !== 'void'));
  const [picked, setPicked] = useState<Set<string>>(() => new Set(bills.length > 0 ? [bills[0].id] : []));
  const chosen = bills.filter((v) => picked.has(v.id));
  const total = chosen.reduce((s, v) => s + v.total, 0);
  const allPicked = bills.length > 0 && chosen.length === bills.length;

  const toggle = (id: string) => {
    const next = new Set(picked);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setPicked(next);
  };

  return (
    <SheetScroll padding={20}>
      <Text variant="titleLarge" style={{ fontWeight: '700' }}>
        Print statement
      </Text>
      <Text style={{ marginTop: 4, color: colors.onSurfaceVariant }}>
        Pick the visits to include. Each shows its items, discounts, payments and balance. From the print dialog you can
        print it or save it as a PDF.
      </Text>
      <View style={{ height: 8 }} />
      {bills.length === 0 ? (
        <Text style={{ paddingVertical: 16, color: colors.outline }}>No bills to print.</Text>
      ) : (
        <>
          <ListTile
            dense
            paddingHorizontal={0}
            onPress={() => setPicked(allPicked ? new Set() : new Set(bills.map((v) => v.id)))}
            leading={
              <Checkbox.Android
                status={allPicked ? 'checked' : chosen.length === 0 ? 'unchecked' : 'indeterminate'}
                onPress={() => setPicked(allPicked ? new Set() : new Set(bills.map((v) => v.id)))}
              />
            }
            title={<Text style={{ fontWeight: '600' }}>All visits ({bills.length})</Text>}
          />
          <Divider />
          {bills.map((v) => (
            <ListTile
              key={v.id}
              dense
              paddingHorizontal={0}
              onPress={() => toggle(v.id)}
              leading={<Checkbox.Android status={picked.has(v.id) ? 'checked' : 'unchecked'} onPress={() => toggle(v.id)} />}
              title={v.title}
              subtitle={[format(v.visitAt ?? v.issuedAt ?? v.createdAt, 'MMM d, y'), v.label].join(' · ')}
              trailing={
                <View style={{ alignItems: 'flex-end', gap: 2 }}>
                  <Text style={{ fontWeight: '600' }}>{formatPeso(v.total)}</Text>
                  <InvoiceStatusChip status={v.status} />
                </View>
              }
            />
          ))}
        </>
      )}
      {chosen.some((v) => v.isDraft) && (
        <Text style={{ marginTop: 8, fontSize: 12, color: colors.onSurfaceVariant }}>
          Drafts print as estimates: their amounts may still change.
        </Text>
      )}
      <Button
        mode="contained"
        icon="print"
        disabled={chosen.length === 0}
        style={{ marginTop: 12 }}
        contentStyle={{ height: 52 }}
        onPress={() => {
          onPrint(patient, chosen);
          close();
        }}
      >
        {chosen.length === 0 ? 'Print' : `Print ${chosen.length} ${chosen.length === 1 ? 'visit' : 'visits'} · ${formatPeso(total)}`}
      </Button>
    </SheetScroll>
  );
}
