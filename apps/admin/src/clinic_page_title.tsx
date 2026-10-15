import { ClinicTitle, useAppTheme, useRailShowsClinic } from '@health/shared';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

/// App bar title for the admin tabs: which tab this is, and which clinic it
/// is showing.
///
/// An admin may run several clinics, and every tab shows one clinic's data,
/// so every tab says which — and lets them switch without going back to the
/// dashboard.
export function ClinicPageTitle({ label }: { label: string }) {
  const { colors } = useAppTheme();
  // Beside a rail that already names the clinic (and switches it), the
  // tab's name is the title.
  if (useRailShowsClinic()) {
    return (
      <Text variant="titleLarge" numberOfLines={1} style={{ fontWeight: '600' }}>
        {label}
      </Text>
    );
  }
  return (
    <View>
      <Text variant="labelMedium" style={{ color: colors.onSurfaceVariant }}>
        {label}
      </Text>
      <ClinicTitle markSize={20} />
    </View>
  );
}
