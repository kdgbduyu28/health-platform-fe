import type { ReactNode } from 'react';
import { View } from 'react-native';
import { Text } from 'react-native-paper';

/// A bold heading over a block of the clinic settings, with an action at
/// its end.
export function SectionTitle({ children, action }: { children: string; action?: ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 8, minHeight: 40 }}>
      <Text variant="titleMedium" style={{ flex: 1, fontWeight: '700' }}>
        {children}
      </Text>
      {action}
    </View>
  );
}
