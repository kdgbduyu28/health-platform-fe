import { useRouter } from 'expo-router';
import { type ReactNode, isValidElement, useContext } from 'react';
import { ScrollView, type StyleProp, View, type ViewStyle } from 'react-native';
import { Appbar, FAB, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import { useClinicNav } from '../app/navigation';
import { useAppTheme } from '../theme/clinic_theme';
import type { IconName } from './icon';
import { OverlayPageContext } from './overlay';

export type FabSpec = { icon: IconName; label?: string; onPress: () => void; disabled?: boolean };

/// A screen: an app bar, a body, and optionally a floating button — what
/// Flutter's Scaffold gave every page.
///
/// The body scrolls by default, its content centred at [maxWidth] while the
/// scroll view itself (and its scrollbar) keeps the page's full width.
export function Page({
  title,
  subtitle,
  actions,
  back,
  fab,
  children,
  scroll = true,
  maxWidth = ContentWidth.wide,
  padding = 16,
  footer,
  belowAppBar,
  appBar = true,
  contentStyle,
  onBack,
}: {
  title?: ReactNode;
  subtitle?: string;
  actions?: ReactNode;
  /// The back button: shown when there is a page to go back to; with a
  /// subpath, always, going there when there is not. False hides it.
  back?: string | false;
  /// What the back button does instead of going back.
  onBack?: () => void;
  fab?: FabSpec | ReactNode;
  children: ReactNode;
  scroll?: boolean;
  maxWidth?: number;
  padding?: number;
  /// Pinned under the body: a bar of buttons, a total.
  footer?: ReactNode;
  /// Pinned under the app bar: tabs, a filter row.
  belowAppBar?: ReactNode;
  appBar?: boolean;
  contentStyle?: StyleProp<ViewStyle>;
}) {
  const { colors } = useAppTheme();
  const router = useRouter();
  const nav = useClinicNav();
  const closeOverlay = useContext(OverlayPageContext);
  const canGoBack = router.canGoBack();
  const showBack = onBack != null || (back !== false && (closeOverlay != null || canGoBack || typeof back === 'string'));
  const goBack = () => {
    if (onBack) onBack();
    else if (closeOverlay) closeOverlay();
    else nav.back(typeof back === 'string' ? back : undefined);
  };

  const body = scroll ? (
    <ScrollView
      style={{ flex: 1 }}
      contentContainerStyle={[{ padding, paddingBottom: fab ? 96 : padding }, contentStyle]}
      keyboardShouldPersistTaps="handled"
    >
      <View style={{ width: '100%', maxWidth, alignSelf: 'center' }}>{children}</View>
    </ScrollView>
  ) : (
    <View style={[{ flex: 1 }, contentStyle]}>{children}</View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: colors.surface }}>
      {appBar && (
        <Appbar.Header statusBarHeight={0} mode="small" style={{ backgroundColor: colors.surface }}>
          {showBack && <Appbar.BackAction onPress={goBack} />}
          <Appbar.Content
            title={
              typeof title === 'string' || title == null ? (
                <View>
                  <Text variant="titleLarge" numberOfLines={1}>
                    {title ?? ''}
                  </Text>
                  {subtitle != null && (
                    <Text variant="bodySmall" numberOfLines={1} style={{ color: colors.onSurfaceVariant }}>
                      {subtitle}
                    </Text>
                  )}
                </View>
              ) : (
                (title as never)
              )
            }
            style={{ marginLeft: showBack ? 0 : 8 }}
          />
          {actions}
        </Appbar.Header>
      )}
      {belowAppBar}
      {body}
      {footer}
      {fab != null &&
        (isValidElement(fab) ? (
          fab
        ) : (
          <FAB
            icon={(fab as FabSpec).icon}
            label={(fab as FabSpec).label}
            onPress={(fab as FabSpec).onPress}
            disabled={(fab as FabSpec).disabled}
            style={{ position: 'absolute', right: 16, bottom: 16 + (footer ? 64 : 0) }}
          />
        ))}
    </View>
  );
}

/// An app bar button.
export function BarAction({
  icon,
  onPress,
  label,
  disabled,
  color,
}: {
  icon: IconName;
  onPress: () => void;
  label: string;
  disabled?: boolean;
  color?: string;
}) {
  return <Appbar.Action icon={icon} onPress={onPress} accessibilityLabel={label} disabled={disabled} color={color} />;
}
