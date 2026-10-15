import {
  AppointmentBoard,
  AppointmentCard,
  AppointmentViewToggle,
  AsyncView,
  BarAction,
  CardColumns,
  Centered,
  ContentWidth,
  EmptyState,
  Page,
  addDays,
  isSameDay,
  refreshAppointments,
  startOfDay,
  useAppTheme,
  useAppointmentView,
  useClinicAppointments,
  useClinicNav,
  withAlpha,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { Text } from 'react-native-paper';

import { ClinicPageTitle } from './clinic_page_title';

export function ScheduleScreen() {
  const { colors } = useAppTheme();
  const qc = useQueryClient();
  const nav = useClinicNav();
  const allAsync = useClinicAppointments();
  const board = useAppointmentView() === 'board';
  const [selected, setSelected] = useState(() => startOfDay(new Date()));

  const all = allAsync.value ?? [];
  const day = all.filter((a) => isSameDay(a.dateTime, selected)).sort((a, b) => a.dateTime.getTime() - b.dateTime.getTime());
  const today = startOfDay(new Date());
  const days = Array.from({ length: 30 }, (_, i) => addDays(today, i - 7));

  return (
    <Page
      title={<ClinicPageTitle label="Schedule" />}
      scroll={false}
      actions={
        <>
          <AppointmentViewToggle />
          <BarAction icon="today" label="Go to today" onPress={() => setSelected(startOfDay(new Date()))} />
        </>
      }
    >
      {/* A strip of days, a week back and three ahead. */}
      <View style={{ height: 88, backgroundColor: colors.surface, borderBottomWidth: 1, borderBottomColor: colors.outlineVariant }}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12, paddingVertical: 8 }}>
          {days.map((d) => {
            const on = isSameDay(d, selected);
            const isToday = isSameDay(d, today);
            const hasAppts = all.some((a) => isSameDay(a.dateTime, d));
            return (
              <Pressable
                key={d.getTime()}
                onPress={() => setSelected(d)}
                accessibilityRole="button"
                accessibilityState={{ selected: on }}
                style={{
                  width: 56,
                  marginHorizontal: 4,
                  borderRadius: 12,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: on ? colors.primary : isToday ? colors.primaryContainer : colors.surfaceContainerLow,
                }}
              >
                <Text style={{ fontSize: 11, color: on ? colors.onPrimary : colors.onSurfaceVariant }}>{format(d, 'EEE')}</Text>
                <Text style={{ marginTop: 2, fontWeight: '700', fontSize: 18, color: on ? colors.onPrimary : colors.onSurface }}>{d.getDate()}</Text>
                {hasAppts && (
                  <View style={{ width: 5, height: 5, borderRadius: 2.5, backgroundColor: on ? withAlpha(colors.onPrimary, 180 / 255) : colors.primary }} />
                )}
              </Pressable>
            );
          })}
        </ScrollView>
      </View>

      <Centered>
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12 }}>
          <Text variant="titleMedium" style={{ flex: 1, fontWeight: '700' }}>
            {format(selected, 'EEEE, MMMM d')}
          </Text>
          <Text style={{ color: colors.onSurfaceVariant, fontSize: 13 }}>
            {day.length} appointment{day.length === 1 ? '' : 's'}
          </Text>
        </View>
      </Centered>

      <View style={{ flex: 1 }}>
        <AsyncView value={allAsync} onRetry={() => void refreshAppointments(qc)}>
          {() =>
            day.length === 0 ? (
              <EmptyState icon="event-available" title="No appointments" />
            ) : board ? (
              <AppointmentBoard appointments={day} />
            ) : (
              <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 16 }}>
                <View style={{ width: '100%', maxWidth: ContentWidth.wide, alignSelf: 'center' }}>
                  <CardColumns>
                    {day.map((a) => (
                      <AppointmentCard key={a.id} appointment={a} showPatient onPress={() => nav.push(`/appointments/${a.id}`)} />
                    ))}
                  </CardColumns>
                </View>
              </ScrollView>
            )
          }
        </AsyncView>
      </View>
    </Page>
  );
}
