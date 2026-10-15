import { BillingScreen, useClinicNav } from '@health/shared';

export default function Billing() {
  const nav = useClinicNav();
  return <BillingScreen onOpenInvoice={(id) => nav.push(`/billing/${id}`)} onOpenPrices={() => nav.push('/prices')} />;
}
