import { useAppTheme } from '@health/shared';
import type { ReactNode } from 'react';
import { Pressable, ScrollView, View, useWindowDimensions } from 'react-native';
import { ActivityIndicator, Button, Dialog, Switch, Text } from 'react-native-paper';

/// A switch with a title and an explanation under it: Flutter's
/// SwitchListTile.
export function SwitchRow({
  title,
  subtitle,
  value,
  onChange,
  disabled,
}: {
  title: string;
  subtitle?: string;
  value: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  const { colors } = useAppTheme();
  return (
    <Pressable
      onPress={() => !disabled && onChange(!value)}
      accessibilityRole="switch"
      accessibilityState={{ checked: value, disabled }}
      style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 8, opacity: disabled ? 0.5 : 1 }}
    >
      <View style={{ flex: 1 }}>
        <Text variant="bodyLarge">{title}</Text>
        {subtitle != null && <Text style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>{subtitle}</Text>}
      </View>
      <Switch value={value} onValueChange={onChange} disabled={disabled} />
    </Pressable>
  );
}

/// An editor in a dialog: a title, a scrolling form, Cancel and a save
/// button.
export function EditorDialog({
  title,
  width = 440,
  children,
  saveLabel,
  busy,
  onCancel,
  onSave,
}: {
  title: string;
  width?: number;
  children: ReactNode;
  saveLabel: string;
  busy: boolean;
  onCancel: () => void;
  onSave: () => void;
}) {
  const { height } = useWindowDimensions();
  return (
    <>
      <Dialog.Title>{title}</Dialog.Title>
      <Dialog.ScrollArea style={{ paddingHorizontal: 0 }}>
        <ScrollView style={{ maxHeight: height * 0.6 }} contentContainerStyle={{ paddingHorizontal: 24, paddingVertical: 8 }}>
          <View style={{ maxWidth: width, width: '100%' }}>{children}</View>
        </ScrollView>
      </Dialog.ScrollArea>
      <Dialog.Actions>
        <Button disabled={busy} onPress={onCancel}>
          Cancel
        </Button>
        <Button mode="contained" disabled={busy} onPress={onSave}>
          {busy ? <ActivityIndicator size={16} /> : saveLabel}
        </Button>
      </Dialog.Actions>
    </>
  );
}

/// A small tag at the end of a row: "Inactive", "Retired".
export function Tag({ label }: { label: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8, borderWidth: 1, borderColor: colors.outlineVariant }}>
      <Text variant="labelMedium">{label}</Text>
    </View>
  );
}
