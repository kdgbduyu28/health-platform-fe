import { Redirect, Stack } from 'expo-router';

import { useRouteClinicSlug } from '../queries/clinic';
import { useAppRole } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { type ClinicTab, ClinicNavScaffold } from './nav_scaffold';
import { clinicHome } from './paths';
import { ClinicScope } from './shell';

/// `/:clinic/_layout` in every app: the clinic's pages as a stack, so a gate
/// opened from inside the app (the patient's own form, say) goes back to
/// where it was opened.
export function ClinicLayout() {
  const { colors } = useAppTheme();
  return (
    <ClinicScope>
      <Stack screenOptions={{ headerShown: false, animation: 'none', contentStyle: { backgroundColor: colors.surface } }} />
    </ClinicScope>
  );
}

/// `/:clinic/(app)/_layout`: the app's pages behind its tabs. A page opened
/// from a tab is pushed onto this stack; picking a tab starts it again.
export function ClinicTabsLayout({ tabs }: { tabs: readonly ClinicTab[] }) {
  const { colors } = useAppTheme();
  return (
    <ClinicNavScaffold tabs={tabs}>
      <Stack screenOptions={{ headerShown: false, animation: 'none', contentStyle: { backgroundColor: colors.surface } }} />
    </ClinicNavScaffold>
  );
}

/// `/:clinic` in the staff apps, which have no public page: their home tab.
export function ClinicHomeRedirect() {
  const slug = useRouteClinicSlug() ?? '';
  const app = useAppRole();
  return <Redirect href={clinicHome(slug, app) as never} />;
}
