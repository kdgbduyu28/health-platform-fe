import { type ClinicTab, ClinicTabsLayout } from '@health/shared';

/// The doctor app's tabs, in order.
const tabs: ClinicTab[] = [
  { path: '/schedule', label: 'Schedule', icon: 'today' },
  { path: '/calendar', label: 'Calendar', icon: 'calendar-view-week' },
  { path: '/patients', label: 'Patients', icon: 'group' },
];

export default function AppLayout() {
  return <ClinicTabsLayout tabs={tabs} />;
}
