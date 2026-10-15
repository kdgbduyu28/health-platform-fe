import {
  AppCard,
  AsyncView,
  BarAction,
  ContentWidth,
  EmptyState,
  Icon,
  InvoiceTile,
  ListTile,
  Page,
  formatPeso,
  useAppTheme,
  useClinicNav,
  useMyInvoices,
  useMyPatient,
  usePrintStatement,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

/// The signed-in patient's bills at this clinic, newest first, with what is
/// still owed on top. Paying happens at the clinic; this is the record.
export function MyBillsScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const async = useMyInvoices();
  const chart = useMyPatient().value ?? null;
  const statement = usePrintStatement();
  const bills = async.value;

  return (
    <Page
      title="Bills & payments"
      maxWidth={ContentWidth.list}
      padding={12}
      actions={
        chart != null && bills != null && bills.length > 0 ? (
          <BarAction icon="print" label="Print statement" onPress={() => statement.choose(chart, bills)} />
        ) : undefined
      }
    >
      <AsyncView value={async} padded onRetry={() => void qc.invalidateQueries({ queryKey: ['patientInvoices'] })}>
        {(bills) => {
          if (bills.length === 0) return <EmptyState icon="receipt-long" title="No bills yet" />;
          const owed = bills.filter((b) => b.isOpen).reduce((sum, b) => sum + b.balance, 0);
          return (
            <View style={{ gap: 8 }}>
              {owed > 0 && (
                <AppCard color={colors.errorContainer}>
                  <ListTile
                    leading={<Icon name="info-outline" color={colors.onErrorContainer} />}
                    title={<Text style={{ fontWeight: '700', color: colors.onErrorContainer }}>{formatPeso(owed)} to settle</Text>}
                    subtitle={<Text style={{ color: colors.onErrorContainer }}>Pay at the clinic's front desk.</Text>}
                  />
                </AppCard>
              )}
              {bills.map((b) => (
                <InvoiceTile key={b.id} invoice={b} onPress={() => nav.push(`/bills/${b.id}`)} />
              ))}
            </View>
          );
        }}
      </AsyncView>
    </Page>
  );
}
