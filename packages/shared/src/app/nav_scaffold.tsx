import { usePathname } from 'expo-router';
import type { ReactNode } from 'react';
import { Pressable, View } from 'react-native';
import { Text, Tooltip } from 'react-native-paper';

import { useMyClinics, useRouteBrandClinic } from '../queries/clinic';
import { ClinicMark } from '../theme/brand';
import { useAppTheme, withAlpha } from '../theme/clinic_theme';
import { Icon, type IconName } from '../ui/icon';
import { useClinicSwitcher } from '../widgets/chrome';
import { RailShowsClinicContext, useWindowSize } from './adaptive';
import { useClinicNav } from './navigation';
import { pathSegments } from './redirect';

/// One tab of an app's main navigation.
export type ClinicTab = {
  /// Under the clinic, starting with `/`: `'/schedule'`.
  path: string;
  label: string;
  icon: IconName;
  selectedIcon?: IconName;
  /// Something waiting on this tab; shown as a count when above zero.
  badge?: number;
};

/// The tab a page belongs to, from its path: `/clinic/patients/42` belongs
/// to Patients. -1 when none matches (a visit, reached from several tabs),
/// and the rail highlights nothing.
export function tabIndexOf(pathname: string, tabs: readonly ClinicTab[]): number {
  const segments = pathSegments(pathname);
  if (segments.length < 2) return -1;
  return tabs.findIndex((t) => t.path === `/${segments[1]}`);
}

/// The app's tabs around [children]: a bottom bar on a phone, a side rail on
/// a tablet or desktop.
///
/// On a phone the bar shows on the tab pages themselves; a page opened from
/// a tab (a visit, a patient, a bill) covers it as usual. On a wider screen
/// the rail stays put beside every page, so the rest of the app is always
/// one click away.
export function ClinicNavScaffold({ tabs, children }: { tabs: readonly ClinicTab[]; children: ReactNode }) {
  const size = useWindowSize();
  const pathname = usePathname();
  const nav = useClinicNav();
  const selected = tabIndexOf(pathname, tabs);
  const onTabPage = selected !== -1 && pathSegments(pathname).length === 2;
  const select = (i: number) => nav.go(tabs[i].path);

  if (size === 'compact') {
    return (
      <View style={{ flex: 1 }}>
        <View style={{ flex: 1 }}>{children}</View>
        {onTabPage && <NavigationBar tabs={tabs} selected={selected} onSelect={select} />}
      </View>
    );
  }
  const extended = size === 'expanded';
  return (
    <View style={{ flex: 1, flexDirection: 'row' }}>
      <NavigationRail tabs={tabs} selected={selected} onSelect={select} extended={extended} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <RailShowsClinicContext.Provider value={extended}>{children}</RailShowsClinicContext.Provider>
      </View>
    </View>
  );
}

function TabIcon({ tab, selected, color }: { tab: ClinicTab; selected: boolean; color: string }) {
  const { colors } = useAppTheme();
  return (
    <View>
      <Icon name={selected ? tab.selectedIcon ?? tab.icon : tab.icon} color={color} />
      {tab.badge != null && tab.badge > 0 && (
        <View
          style={{
            position: 'absolute',
            top: -4,
            right: -10,
            minWidth: 16,
            height: 16,
            paddingHorizontal: 4,
            borderRadius: 8,
            backgroundColor: colors.error,
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text style={{ color: colors.onError, fontSize: 11, lineHeight: 14 }}>{tab.badge}</Text>
        </View>
      )}
    </View>
  );
}

function NavigationBar({ tabs, selected, onSelect }: { tabs: readonly ClinicTab[]; selected: number; onSelect: (i: number) => void }) {
  const { colors } = useAppTheme();
  return (
    <View
      accessibilityRole="tablist"
      style={{ flexDirection: 'row', height: 80, backgroundColor: colors.surfaceContainer, paddingTop: 12, paddingBottom: 16 }}
    >
      {tabs.map((t, i) => {
        const on = i === selected;
        return (
          <Pressable
            key={t.path}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            accessibilityLabel={t.label}
            onPress={() => onSelect(i)}
            style={{ flex: 1, alignItems: 'center', gap: 4 }}
          >
            <View
              style={{
                width: 64,
                height: 32,
                borderRadius: 16,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: on ? colors.secondaryContainer : 'transparent',
              }}
            >
              <TabIcon tab={t} selected={on} color={on ? colors.onSecondaryContainer : colors.onSurfaceVariant} />
            </View>
            <Text
              numberOfLines={1}
              style={{ fontSize: 12, fontWeight: on ? '700' : '500', color: on ? colors.onSurface : colors.onSurfaceVariant }}
            >
              {t.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function NavigationRail({
  tabs,
  selected,
  onSelect,
  extended,
}: {
  tabs: readonly ClinicTab[];
  selected: number;
  onSelect: (i: number) => void;
  extended: boolean;
}) {
  const { colors } = useAppTheme();
  return (
    <View
      accessibilityRole="tablist"
      style={{
        width: extended ? 232 : 80,
        backgroundColor: colors.surfaceContainerLow,
        paddingHorizontal: extended ? 12 : 0,
        alignItems: extended ? 'stretch' : 'center',
      }}
    >
      <RailHeader extended={extended} />
      {tabs.map((t, i) => {
        const on = i === selected;
        const fg = on ? colors.onSecondaryContainer : colors.onSurfaceVariant;
        if (extended) {
          return (
            <Pressable
              key={t.path}
              accessibilityRole="tab"
              accessibilityState={{ selected: on }}
              onPress={() => onSelect(i)}
              style={({ hovered }: { hovered?: boolean }) => ({
                flexDirection: 'row',
                alignItems: 'center',
                gap: 12,
                height: 56,
                paddingHorizontal: 16,
                borderRadius: 28,
                marginBottom: 4,
                backgroundColor: on ? colors.secondaryContainer : hovered ? withAlpha(colors.onSurface, 0.06) : 'transparent',
              })}
            >
              <TabIcon tab={t} selected={on} color={fg} />
              <Text style={{ color: on ? colors.onSecondaryContainer : colors.onSurfaceVariant, fontWeight: on ? '700' : '500' }}>
                {t.label}
              </Text>
            </Pressable>
          );
        }
        return (
          <Pressable
            key={t.path}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            accessibilityLabel={t.label}
            onPress={() => onSelect(i)}
            style={{ alignItems: 'center', gap: 4, marginBottom: 12, width: 80 }}
          >
            <View
              style={{
                width: 56,
                height: 32,
                borderRadius: 16,
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: on ? colors.secondaryContainer : 'transparent',
              }}
            >
              <TabIcon tab={t} selected={on} color={fg} />
            </View>
            <Text numberOfLines={1} style={{ fontSize: 12, fontWeight: on ? '700' : '500', color: on ? colors.onSurface : colors.onSurfaceVariant }}>
              {t.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/// The clinic's mark, and on a desktop its name. For someone at several
/// clinics it is also the switcher, since the page titles beside it then
/// name the page rather than the clinic.
function RailHeader({ extended }: { extended: boolean }) {
  const clinic = useRouteBrandClinic();
  const clinics = useMyClinics().value ?? [];
  const switcher = useClinicSwitcher();
  const canSwitch = clinics.length > 1;
  const header = (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4, paddingHorizontal: extended ? 8 : 0 }}>
      <ClinicMark clinic={clinic} size={40} />
      {extended && (
        <Text variant="titleSmall" numberOfLines={2} style={{ flex: 1, fontWeight: '700' }}>
          {clinic?.name ?? ''}
        </Text>
      )}
      {extended && canSwitch && <Icon name="expand-more" size={20} />}
    </View>
  );
  return (
    <View style={{ paddingTop: 8, paddingBottom: 16 }}>
      {canSwitch ? (
        <Tooltip title="Switch clinic">
          <Pressable onPress={switcher} accessibilityRole="button" accessibilityLabel="Switch clinic" style={{ borderRadius: 12 }}>
            {header}
          </Pressable>
        </Tooltip>
      ) : (
        header
      )}
    </View>
  );
}
