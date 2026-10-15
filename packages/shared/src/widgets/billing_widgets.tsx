import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { Pressable, View } from 'react-native';
import { Button, ProgressBar, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import { type Invoice, type InvoiceStatus, invoiceStatusMeta } from '../models/invoice';
import { formatPeso } from '../models/money';
import { invalidateBilling, useAppointmentInvoice, useCanBill } from '../queries/billing';
import { useRepository } from '../state/platform';
import { useAppTheme, useReadable, withAlpha } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';
import { useOverlay } from '../ui/overlay';

export function InvoiceStatusChip({ status }: { status: InvoiceStatus }) {
  const readable = useReadable();
  const color = readable(invoiceStatusMeta[status].color);
  return (
    <View
      style={{
        alignSelf: 'flex-end',
        paddingHorizontal: 8,
        paddingVertical: 3,
        borderRadius: 20,
        backgroundColor: withAlpha(color, 28 / 255),
        borderWidth: 1,
        borderColor: withAlpha(color, 80 / 255),
      }}
    >
      <Text style={{ color, fontSize: 12, fontWeight: '600' }}>{invoiceStatusMeta[status].label}</Text>
    </View>
  );
}

/// One bill in a list: what it is for, when, how much, and what is left.
export function InvoiceTile({
  invoice: v,
  onPress,
  showPatient = false,
}: {
  invoice: Invoice;
  /// Absent where the app has no bill page (the doctor app).
  onPress?: () => void;
  showPatient?: boolean;
}) {
  const { colors } = useAppTheme();
  const when = v.visitAt ?? v.issuedAt ?? v.createdAt;
  return (
    <AppCard style={{ marginBottom: 8 }}>
      <ListTile
        onPress={onPress}
        paddingHorizontal={16}
        style={{ paddingRight: 12 }}
        title={<Text style={{ fontWeight: '600' }}>{showPatient && v.patient != null ? v.patient.name : v.title}</Text>}
        subtitle={[...(showPatient && v.patient != null ? [v.title] : []), v.label, format(when, 'MMM d, y')].join(' · ')}
        trailing={
          <View style={{ alignItems: 'flex-end', gap: 4 }}>
            <Text style={{ fontWeight: '600' }}>{formatPeso(v.total)}</Text>
            {v.isOpen && v.amountPaid > 0 ? (
              <Text style={{ fontSize: 12, color: colors.error }}>{formatPeso(v.balance)} left</Text>
            ) : (
              <InvoiceStatusChip status={v.status} />
            )}
          </View>
        }
      />
    </AppCard>
  );
}

/// The bill for one visit, on an appointment screen: its state, or — for the
/// front desk and admins once the patient is in — a button to start one.
export function VisitBillSection({ appointment, onOpenInvoice }: { appointment: Appointment; onOpenInvoice: (invoiceId: string) => void }) {
  const { colors } = useAppTheme();
  const canBill = useCanBill().value ?? false;
  const billAsync = useAppointmentInvoice(appointment.id);
  const repo = useRepository();
  const qc = useQueryClient();
  const overlay = useOverlay();
  const billable = appointment.status === 'arrived' || appointment.status === 'in_consultation' || appointment.status === 'completed';
  const bill = billAsync.value ?? null;
  if (bill == null && !(canBill && billable)) return null;

  return (
    <View style={{ marginBottom: 12, padding: 16, borderRadius: 16, backgroundColor: colors.surfaceContainerLow }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Icon name="receipt-long" size={16} color={colors.primary} />
        <Text style={{ fontWeight: '600', color: colors.onSurfaceVariant }}>Bill</Text>
      </View>
      <View style={{ height: 8 }} />
      {billAsync.isLoading && bill == null ? (
        <ProgressBar indeterminate />
      ) : bill != null ? (
        <Pressable onPress={() => onOpenInvoice(bill.id)} style={{ flexDirection: 'row', alignItems: 'center', gap: 8, borderRadius: 8 }}>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 18, fontWeight: '700' }}>{formatPeso(bill.total)}</Text>
            <Text style={{ color: colors.onSurfaceVariant }}>
              {bill.isOpen && bill.amountPaid > 0 ? `${bill.label} · ${formatPeso(bill.balance)} still owed` : bill.label}
            </Text>
          </View>
          <InvoiceStatusChip status={bill.status} />
          <Icon name="chevron-right" />
        </Pressable>
      ) : (
        <Button
          mode="contained-tonal"
          icon="add"
          style={{ alignSelf: 'flex-start' }}
          onPress={async () => {
            try {
              const id = await repo.createInvoiceForAppointment(appointment.id);
              void invalidateBilling(qc);
              onOpenInvoice(id);
            } catch (e) {
              overlay.snack(describeError(e));
            }
          }}
        >
          Create bill
        </Button>
      )}
    </View>
  );
}
