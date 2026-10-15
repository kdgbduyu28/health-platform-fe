import { type ClinicTab, ClinicTabsLayout } from '@health/shared';

/// The patient app's tabs, in order.
const tabs: ClinicTab[] = [
  { path: '/home', label: 'Home', icon: 'home', selectedIcon: 'home' },
  { path: '/appointments', label: 'Appointments', icon: 'calendar-today', selectedIcon: 'calendar-today' },
  { path: '/calendar', label: 'Calendar', icon: 'calendar-view-week', selectedIcon: 'calendar-view-week' },
  { path: '/profile', label: 'Profile', icon: 'person-outline', selectedIcon: 'person' },
];

export default function AppLayout() {
  return <ClinicTabsLayout tabs={tabs} />;
}
