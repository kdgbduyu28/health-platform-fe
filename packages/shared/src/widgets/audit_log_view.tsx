import { format } from 'date-fns';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, ScrollView, View } from 'react-native';
import { ActivityIndicator, Button, Chip, Text } from 'react-native-paper';

import { ContentWidth } from '../app/adaptive';
import { type AuditArea, type AuditEntry, auditAreaMeta, auditAreas } from '../models/audit_entry';
import { useCurrentClinicId } from '../queries/clinic';
import { fetchAuditPage } from '../queries/misc';
import { usePlatform } from '../state/platform';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon, type IconName } from '../ui/icon';
import { AppCard, ListTile } from '../ui/kit';
import { SheetScroll, useOverlay } from '../ui/overlay';
import { Page } from '../ui/page';
import { isSameDay, startOfDay } from '../util/dates';

/// The clinic's activity log: who changed what, and when. Admins only.
///
/// A page of its own in the admin app, with a filter by area. The patient
/// page shows the same list for one chart (AuditLogView with a `patientId`).
export function AuditLogScreen({ onOpenPatient }: { onOpenPatient?: (patientId: string) => void }) {
  const [area, setArea] = useState<AuditArea | null>(null);
  return (
    <Page title="Activity log" scroll={false} back="/settings">
      <View style={{ width: '100%', maxWidth: ContentWidth.list + 32, alignSelf: 'center' }}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 8, gap: 8 }}>
          {[null, ...auditAreas].map((a) => (
            <Chip key={a ?? 'all'} mode="outlined" selected={area === a} showSelectedCheck onPress={() => setArea(a)}>
              {a == null ? 'Everything' : auditAreaMeta[a].label}
            </Chip>
          ))}
        </ScrollView>
      </View>
      <View style={{ flex: 1 }}>
        <AuditLogView key={area ?? 'all'} area={area} onOpenPatient={onOpenPatient} />
      </View>
    </Page>
  );
}

function dayLabel(d: Date): string {
  const today = startOfDay(new Date());
  if (isSameDay(d, today)) return 'Today';
  const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1);
  if (isSameDay(d, yesterday)) return 'Yesterday';
  return format(d, d.getFullYear() === today.getFullYear() ? 'EEEE, d MMMM' : 'EEEE, d MMMM y');
}

/// The log as a list, newest first, grouped by day, loading older entries as
/// it is scrolled. With [patientId], only the changes to that chart.
export function AuditLogView({
  patientId = null,
  area = null,
  onOpenPatient,
}: {
  patientId?: string | null;
  area?: AuditArea | null;
  onOpenPatient?: (patientId: string) => void;
}) {
  const { colors } = useAppTheme();
  const { supabase } = usePlatform();
  const clinicId = useCurrentClinicId();
  const openEntry = useAuditEntrySheet();
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const busy = useRef(false);

  const load = useCallback(
    async (reset = false) => {
      if (clinicId == null || busy.current) return;
      busy.current = true;
      setLoading(true);
      setError(null);
      const before = reset ? [] : entries;
      if (reset) {
        setEntries([]);
        setHasMore(true);
      }
      try {
        const page = await fetchAuditPage(supabase, {
          clinicId,
          patientId,
          area,
          beforeId: before.length === 0 ? null : before[before.length - 1].id,
        });
        setEntries([...before, ...page.entries]);
        setHasMore(page.hasMore);
      } catch (e) {
        setError(e);
      } finally {
        busy.current = false;
        setLoading(false);
      }
    },
    [clinicId, supabase, patientId, area, entries],
  );

  useEffect(() => {
    void load(true);
    // Once the clinic is known, and again if it changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clinicId]);

  if (entries.length === 0) {
    if (error != null) {
      return <Message icon="error-outline" text={describeError(error)} action={<Button onPress={() => void load()}>Retry</Button>} />;
    }
    if (loading || clinicId == null) {
      return (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <ActivityIndicator />
        </View>
      );
    }
    return <Message icon="history" text={patientId == null ? 'No changes recorded yet.' : 'No changes to this patient recorded yet.'} />;
  }

  // Day headers between the entries.
  const items: (Date | AuditEntry)[] = [];
  let day: Date | null = null;
  for (const e of entries) {
    const d = startOfDay(e.createdAt);
    if (day == null || d.getTime() !== day.getTime()) items.push(d);
    day = d;
    items.push(e);
  }

  return (
    <FlatList
      data={items}
      keyExtractor={(item) => (item instanceof Date ? `d${item.getTime()}` : `e${item.id}`)}
      contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 32, width: '100%', maxWidth: ContentWidth.list, alignSelf: 'center' }}
      onEndReached={() => hasMore && !loading && error == null && void load()}
      onEndReachedThreshold={0.6}
      renderItem={({ item }) =>
        item instanceof Date ? (
          <Text variant="labelLarge" style={{ paddingHorizontal: 4, paddingTop: 16, paddingBottom: 6, color: colors.onSurfaceVariant }}>
            {dayLabel(item)}
          </Text>
        ) : (
          <EntryTile entry={item} showPatient={patientId == null} onPress={() => openEntry(item, patientId == null ? onOpenPatient : undefined)} />
        )
      }
      ListFooterComponent={
        error != null ? (
          <View style={{ alignItems: 'center' }}>
            <Button onPress={() => void load()}>Retry</Button>
          </View>
        ) : hasMore ? (
          <View style={{ padding: 16, alignItems: 'center' }}>
            <ActivityIndicator />
          </View>
        ) : (
          <Text style={{ padding: 16, textAlign: 'center', color: colors.onSurfaceVariant }}>That is everything.</Text>
        )
      }
    />
  );
}

function Message({ icon, text, action }: { icon: IconName; text: string; action?: React.ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <Icon name={icon} size={40} color={colors.onSurfaceVariant} />
      <Text style={{ marginTop: 12, textAlign: 'center', color: colors.onSurfaceVariant }}>{text}</Text>
      {action != null && <View style={{ marginTop: 8 }}>{action}</View>}
    </View>
  );
}

function iconOf(e: AuditEntry): IconName {
  if (e.action === 'insert') return 'add-circle-outline';
  if (e.action === 'delete') return 'remove-circle-outline';
  switch (e.area) {
    case 'patients':
      return 'person-outline';
    case 'visits':
      return 'event';
    case 'billing':
      return 'receipt-long';
    default:
      return 'edit';
  }
}

function byLine(e: AuditEntry): string {
  const role = e.actorRoleLabel;
  return role == null ? e.actorLabel : `${e.actorLabel} (${role})`;
}

function EntryTile({ entry: e, showPatient, onPress }: { entry: AuditEntry; showPatient: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  const preview =
    e.action === 'update'
      ? e.changes
          .slice(0, 2)
          .map((c) => (c.before == null ? `${c.label} ${c.after}` : `${c.label}: ${c.before} → ${c.after}`))
          .join(' · ')
      : null;
  return (
    <AppCard style={{ marginBottom: 6 }}>
      <ListTile
        onPress={onPress}
        leading={<Icon name={iconOf(e)} color={e.action === 'delete' ? colors.error : colors.primary} />}
        title={
          <Text>
            <Text style={{ fontWeight: '600' }}>{e.headline}</Text>
            {showPatient && e.patientName != null && <Text>{` · ${e.patientName}`}</Text>}
          </Text>
        }
        subtitle={
          <View>
            {preview != null && preview !== '' && (
              <Text numberOfLines={2} style={{ color: colors.onSurfaceVariant }}>
                {preview}
              </Text>
            )}
            <Text variant="bodySmall" style={{ color: colors.onSurfaceVariant }}>
              {byLine(e)} · {format(e.createdAt, 'h:mm a')}
            </Text>
          </View>
        }
        trailing={<Icon name="chevron-right" />}
      />
    </AppCard>
  );
}

/// Everything one entry recorded: every field, before and after.
export function useAuditEntrySheet(): (entry: AuditEntry, onOpenPatient?: (patientId: string) => void) => void {
  const overlay = useOverlay();
  return (e, onOpenPatient) =>
    void overlay.showSheet((close) => <AuditEntrySheet entry={e} onOpenPatient={onOpenPatient} close={() => close()} />);
}

function AuditEntrySheet({ entry: e, onOpenPatient, close }: { entry: AuditEntry; onOpenPatient?: (patientId: string) => void; close: () => void }) {
  const { colors } = useAppTheme();
  const changes = e.changes;
  const patientId = e.patientId;
  return (
    <SheetScroll padding={24}>
      <Text variant="titleLarge" style={{ fontWeight: '600' }}>
        {e.headline}
      </Text>
      {e.patientName != null && (
        <Text variant="titleMedium" style={{ marginTop: 2 }}>
          {e.patientName}
        </Text>
      )}
      <Text style={{ marginTop: 8, color: colors.onSurfaceVariant }}>
        {byLine(e)}
        {'\n'}
        {format(e.createdAt, 'EEEE, d MMMM y · h:mm:ss a')}
      </Text>
      <View style={{ height: 16 }} />
      {changes.length === 0 ? (
        <Text style={{ color: colors.onSurfaceVariant }}>No details were recorded.</Text>
      ) : (
        changes.map((c, i) => (
          <View key={i} style={{ marginBottom: 12 }}>
            <Text variant="labelMedium" style={{ color: colors.onSurfaceVariant }}>
              {c.label}
            </Text>
            {c.before != null && c.after != null ? (
              <>
                <Text style={{ marginTop: 2, color: colors.onSurfaceVariant, textDecorationLine: 'line-through' }}>{c.before}</Text>
                <Text>{c.after}</Text>
              </>
            ) : (
              <Text style={[{ marginTop: 2 }, e.action === 'delete' && { color: colors.onSurfaceVariant }]}>{c.after ?? c.before}</Text>
            )}
          </View>
        ))
      )}
      {onOpenPatient != null && patientId != null && e.action !== 'delete' && (
        <Button
          mode="outlined"
          icon="person-outline"
          style={{ alignSelf: 'flex-start' }}
          onPress={() => {
            close();
            onOpenPatient(patientId);
          }}
        >
          Open patient
        </Button>
      )}
    </SheetScroll>
  );
}
