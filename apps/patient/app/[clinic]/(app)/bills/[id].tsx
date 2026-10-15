import { InvoiceScreen } from '@health/shared';
import { useLocalSearchParams } from 'expo-router';

export default function Bill() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <InvoiceScreen key={id} invoiceId={id} />;
}
