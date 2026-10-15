import { type ReactNode, useState } from 'react';
import { Pressable, type StyleProp, View, type ViewStyle } from 'react-native';
import { Divider, IconButton, Menu, Text, TouchableRipple, Tooltip } from 'react-native-paper';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';

import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { Icon, type IconName } from './icon';

/// Empty space: Flutter's SizedBox between two widgets.
export function Gap({ size = 8, horizontal = false }: { size?: number; horizontal?: boolean }) {
  return <View style={horizontal ? { width: size } : { height: size }} />;
}

/// Children side by side, wrapping onto the next line when they run out of
/// room: Flutter's Wrap.
export function Wrap({
  children,
  spacing = 8,
  runSpacing = 8,
  style,
  align = 'center',
}: {
  children: ReactNode;
  spacing?: number;
  runSpacing?: number;
  style?: StyleProp<ViewStyle>;
  align?: 'center' | 'flex-start' | 'flex-end';
}) {
  return (
    <View style={[{ flexDirection: 'row', flexWrap: 'wrap', columnGap: spacing, rowGap: runSpacing, alignItems: align }, style]}>
      {children}
    </View>
  );
}

/// A card as the apps draw them: flat, rounded, with a faint outline — the
/// Flutter theme's CardTheme.
export function AppCard({
  children,
  onPress,
  style,
  padding = 0,
  color,
  disabled,
}: {
  children: ReactNode;
  onPress?: () => void;
  style?: StyleProp<ViewStyle>;
  padding?: number;
  color?: string;
  disabled?: boolean;
}) {
  const { colors, dark } = useAppTheme();
  const frame: ViewStyle = {
    borderRadius: 16,
    borderWidth: 1,
    borderColor: withAlpha(colors.outlineVariant, dark ? 160 / 255 : 110 / 255),
    backgroundColor: color ?? colors.surfaceContainerLow,
    overflow: 'hidden',
  };
  if (onPress == null) return <View style={[frame, { padding }, style]}>{children}</View>;
  return (
    <View style={[frame, style]}>
      <TouchableRipple onPress={onPress} disabled={disabled} style={{ padding }}>
        <View>{children}</View>
      </TouchableRipple>
    </View>
  );
}

/// One row of a list: something at the start, a title and a line or two
/// under it, something at the end. Flutter's ListTile.
export function ListTile({
  leading,
  title,
  subtitle,
  trailing,
  onPress,
  onLongPress,
  dense = false,
  selected = false,
  disabled = false,
  paddingHorizontal = 16,
  style,
  titleStyle,
}: {
  leading?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  trailing?: ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
  dense?: boolean;
  selected?: boolean;
  disabled?: boolean;
  paddingHorizontal?: number;
  style?: StyleProp<ViewStyle>;
  titleStyle?: StyleProp<import('react-native').TextStyle>;
}) {
  const { colors } = useAppTheme();
  const content = (
    <View
      style={[
        {
          flexDirection: 'row',
          alignItems: 'center',
          paddingHorizontal,
          paddingVertical: dense ? 6 : 10,
          minHeight: dense ? 48 : 56,
          gap: 16,
          opacity: disabled ? 0.5 : 1,
          backgroundColor: selected ? withAlpha(colors.primary, 0.08) : undefined,
        },
        style,
      ]}
    >
      {leading != null && <View>{leading}</View>}
      <View style={{ flex: 1, minWidth: 0 }}>
        {typeof title === 'string' ? (
          <Text variant={dense ? 'bodyMedium' : 'bodyLarge'} style={[selected && { color: colors.primary }, titleStyle]}>
            {title}
          </Text>
        ) : (
          title
        )}
        {subtitle != null &&
          (typeof subtitle === 'string' ? (
            <Text variant="bodyMedium" style={{ color: colors.onSurfaceVariant }}>
              {subtitle}
            </Text>
          ) : (
            subtitle
          ))}
      </View>
      {trailing != null && <View>{trailing}</View>}
    </View>
  );
  if (onPress == null && onLongPress == null) return content;
  return (
    <TouchableRipple onPress={onPress} onLongPress={onLongPress} disabled={disabled} accessibilityRole="button">
      {content}
    </TouchableRipple>
  );
}

/// A round badge with initials or an icon: Flutter's CircleAvatar.
export function Avatar({
  label,
  icon,
  size = 40,
  color,
  textColor,
}: {
  label?: string;
  icon?: IconName;
  size?: number;
  color?: string;
  textColor?: string;
}) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: color ?? colors.primaryContainer,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      {icon != null ? (
        <Icon name={icon} size={size * 0.55} color={textColor ?? colors.onPrimaryContainer} />
      ) : (
        <Text style={{ color: textColor ?? colors.onPrimaryContainer, fontWeight: '600', fontSize: size * 0.38 }}>{label}</Text>
      )}
    </View>
  );
}

/// A bold heading over a group of rows or cards.
export function SectionHeader({ children, trailing, style }: { children: ReactNode; trailing?: ReactNode; style?: StyleProp<ViewStyle> }) {
  return (
    <View style={[{ flexDirection: 'row', alignItems: 'center', marginTop: 16, marginBottom: 8 }, style]}>
      <Text variant="titleMedium" style={{ flex: 1, fontWeight: '700' }}>
        {children}
      </Text>
      {trailing}
    </View>
  );
}

/// A quiet line of explanation.
export function Hint({ children, style }: { children: ReactNode; style?: StyleProp<import('react-native').TextStyle> }) {
  const { colors } = useAppTheme();
  return <Text style={[{ color: colors.onSurfaceVariant, fontSize: 13, lineHeight: 18 }, style]}>{children}</Text>;
}

export type MenuEntry =
  | {
      label: string;
      icon?: IconName;
      onPress: () => void;
      disabled?: boolean;
      destructive?: boolean;
    }
  | 'divider'
  | { header: string };

/// A button that opens a list of actions: Flutter's PopupMenuButton.
export function MenuButton({
  icon = 'more-vert',
  label = 'More',
  items,
  anchor,
  iconColor,
}: {
  icon?: IconName;
  label?: string;
  items: MenuEntry[];
  /// Something other than an icon button to open it with.
  anchor?: (open: () => void) => ReactNode;
  iconColor?: string;
}) {
  const [visible, setVisible] = useState(false);
  const { colors } = useAppTheme();
  const open = () => setVisible(true);
  return (
    <Menu
      visible={visible}
      onDismiss={() => setVisible(false)}
      anchorPosition="bottom"
      anchor={
        anchor ? (
          anchor(open)
        ) : (
          <Tooltip title={label}>
            <IconButton icon={icon} onPress={open} accessibilityLabel={label} iconColor={iconColor} />
          </Tooltip>
        )
      }
    >
      {items.map((item, i) => {
        if (item === 'divider') return <Divider key={i} />;
        if ('header' in item) {
          return (
            <Text key={i} style={{ paddingHorizontal: 16, paddingVertical: 8, color: colors.onSurfaceVariant, fontSize: 13 }}>
              {item.header}
            </Text>
          );
        }
        return (
          <Menu.Item
            key={i}
            leadingIcon={item.icon}
            title={item.label}
            disabled={item.disabled}
            titleStyle={item.destructive ? { color: colors.error } : undefined}
            onPress={() => {
              setVisible(false);
              item.onPress();
            }}
          />
        );
      })}
    </Menu>
  );
}

/// A row of tabs over a page's sections: Flutter's TabBar. The page shows
/// the section for [value].
export function Tabs<T extends string>({
  value,
  onChange,
  tabs,
  scrollable = false,
}: {
  value: T;
  onChange: (value: T) => void;
  tabs: readonly { value: T; label: string; icon?: IconName; badge?: number }[];
  scrollable?: boolean;
}) {
  const { colors } = useAppTheme();
  return (
    <View
      style={{
        flexDirection: 'row',
        borderBottomWidth: 1,
        borderBottomColor: colors.surfaceVariant,
        ...(scrollable ? { overflow: 'scroll' as never } : null),
      }}
      accessibilityRole="tablist"
    >
      {tabs.map((t) => {
        const selected = t.value === value;
        return (
          <Pressable
            key={t.value}
            onPress={() => onChange(t.value)}
            accessibilityRole="tab"
            accessibilityState={{ selected }}
            style={({ hovered }: { hovered?: boolean }) => ({
              flex: scrollable ? undefined : 1,
              paddingHorizontal: 16,
              paddingVertical: 12,
              alignItems: 'center',
              backgroundColor: hovered ? withAlpha(colors.onSurface, 0.06) : undefined,
            })}
          >
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              {t.icon && <Icon name={t.icon} size={20} color={selected ? colors.primary : colors.onSurfaceVariant} />}
              <Text style={{ color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: '600' }}>{t.label}</Text>
              {t.badge != null && t.badge > 0 && (
                <View style={{ backgroundColor: colors.error, borderRadius: 8, paddingHorizontal: 5, minWidth: 16 }}>
                  <Text style={{ color: colors.onError, fontSize: 11, textAlign: 'center' }}>{t.badge}</Text>
                </View>
              )}
            </View>
            <View
              style={{
                position: 'absolute',
                left: 12,
                right: 12,
                bottom: 0,
                height: 3,
                borderTopLeftRadius: 3,
                borderTopRightRadius: 3,
                backgroundColor: selected ? colors.primary : 'transparent',
              }}
            />
          </Pressable>
        );
      })}
    </View>
  );
}

/// A box of explanation with an icon: a tip, a warning, a "nothing here".
export function Notice({
  icon = 'info-outline',
  children,
  tone = 'neutral',
  action,
  style,
}: {
  icon?: IconName;
  children: ReactNode;
  tone?: 'neutral' | 'primary' | 'error' | 'warning';
  action?: ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  const { colors } = useAppTheme();
  const palette = {
    neutral: { bg: colors.surfaceContainerHigh, fg: colors.onSurfaceVariant },
    primary: { bg: colors.primaryContainer, fg: colors.onPrimaryContainer },
    error: { bg: colors.errorContainer, fg: colors.onErrorContainer },
    warning: { bg: withAlpha('#FFB300', 0.18), fg: colors.onSurface },
  }[tone];
  return (
    <View style={[{ flexDirection: 'row', alignItems: 'center', gap: 12, padding: 12, borderRadius: 12, backgroundColor: palette.bg }, style]}>
      <Icon name={icon} size={20} color={palette.fg} />
      <View style={{ flex: 1 }}>{typeof children === 'string' ? <Text style={{ color: palette.fg }}>{children}</Text> : children}</View>
      {action}
    </View>
  );
}

let gradientIds = 0;

/// A box filled with a diagonal gradient from [from] to [to] (by default the
/// clinic's primary to secondary colour).
export function GradientBox({
  children,
  from,
  to,
  radius = 20,
  style,
}: {
  children: ReactNode;
  from?: string;
  to?: string;
  radius?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const { colors } = useAppTheme();
  const [id] = useState(() => `g${++gradientIds}`);
  return (
    <View style={[{ borderRadius: radius, overflow: 'hidden' }, style]}>
      <Svg style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} width="100%" height="100%" preserveAspectRatio="none">
        <Defs>
          <LinearGradient id={id} x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={from ?? colors.primary} />
            <Stop offset="1" stopColor={to ?? colors.secondary} />
          </LinearGradient>
        </Defs>
        <Rect width="100%" height="100%" fill={`url(#${id})`} />
      </Svg>
      {children}
    </View>
  );
}

/// The middle of an empty list: an icon, a line saying so, maybe a button.
export function EmptyState({ icon, title, message, action }: { icon: IconName; title: string; message?: string; action?: ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ alignItems: 'center', padding: 32, gap: 8 }}>
      <Icon name={icon} size={56} color={colors.outline} />
      <Text variant="titleMedium" style={{ textAlign: 'center' }}>
        {title}
      </Text>
      {message != null && <Text style={{ color: colors.onSurfaceVariant, textAlign: 'center', maxWidth: 420 }}>{message}</Text>}
      {action != null && <View style={{ marginTop: 8 }}>{action}</View>}
    </View>
  );
}
