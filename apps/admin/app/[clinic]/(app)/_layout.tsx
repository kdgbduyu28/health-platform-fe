import { type ClinicTab, ClinicTabsLayout, usePendingStaffRequests } from '@health/shared';

export default function AppLayout() {
  // New staff waiting for approval surface on the Clinic tab from anywhere.
  const pending = usePendingStaffRequests().length;
  const tabs: ClinicTab[] = [
    { path: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
    { path: '/schedule', label: 'Schedule', icon: 'calendar-month' },
    { path: '/calendar', label: 'Calendar', icon: 'calendar-view-week' },
    { path: '/patients', label: 'Patients', icon: 'group' },
    { path: '/billing', label: 'Billing', icon: 'receipt-long' },
    { path: '/settings', label: 'Clinic', icon: 'storefront', badge: pending },
  ];
  return <ClinicTabsLayout tabs={tabs} />;
}
