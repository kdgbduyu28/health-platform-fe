import { type ClinicTab, ClinicTabsLayout } from '@health/shared';

/// The front desk app's tabs, in order.
const tabs: ClinicTab[] = [
  { path: '/check-in', label: 'Check-In', icon: 'how-to-reg' },
  { path: '/calendar', label: 'Calendar', icon: 'calendar-view-week' },
  { path: '/walkin', label: 'Walk-In', icon: 'add-circle-outline', selectedIcon: 'add-circle' },
  { path: '/patients', label: 'Patients', icon: 'group' },
  { path: '/billing', label: 'Billing', icon: 'receipt-long' },
];

export default function AppLayout() {
  return <ClinicTabsLayout tabs={tabs} />;
}
