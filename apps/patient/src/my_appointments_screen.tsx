import {
  type Appointment,
  AppointmentCard,
  AsyncView,
  ContentWidth,
  EmptyState,
  Page,
  PastAppointmentsList,
  Tabs,
  holdsTime,
  isOnSite,
  refreshAppointments,
  useClinicNav,
  useMyAppointments,
  useMyPatient,
} from '@health/shared';
import { useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { FlatList, View } from 'react-native';

type Tab = 'upcoming' | 'past';

export function MyAppointmentsScreen() {
  const qc = useQueryClient();
  const nav = useClinicNav();
  const allAsync = useMyAppointments();
  const me = useMyPatient().value ?? null;
  const [tab, setTab] = useState<Tab>('upcoming');
  const now = Date.now();

  // Tab labels carry counts, so they can only be built once the data is in.
  const all = allAsync.value ?? [];
  // Upcoming: still to come, or happening now (checked in, or with the
  // doctor, even though the start time has passed).
  const isUpcoming = (a: Appointment) => holdsTime(a.status) && (a.dateTime.getTime() > now || isOnSite(a.status));
  const upcoming = all.filter(isUpcoming).sort((a, b) => a.dateTime.getTime() - b.dateTime.getTime());
  // Recent past visits are in the loaded window; older ones page in below.
  const past = all.filter((a) => !isUpcoming(a)).sort((a, b) => b.dateTime.getTime() - a.dateTime.getTime());
  const open = (a: Appointment) => nav.push(`/appointments/${a.id}`);

  return (
    <Page
      title="My Appointments"
      scroll={false}
      belowAppBar={
        <Tabs
          value={tab}
          onChange={setTab}
          tabs={[
            { value: 'upcoming', label: `Upcoming (${upcoming.length})` },
            { value: 'past', label: 'Past' },
          ]}
        />
      }
      fab={{ icon: 'add', label: 'Book', onPress: () => nav.push('/book') }}
    >
      <AsyncView value={allAsync} onRetry={() => void refreshAppointments(qc)}>
        {() =>
          tab === 'upcoming' ? (
            upcoming.length === 0 ? (
              <EmptyState icon="calendar-today" title="No upcoming appointments" message="Tap + to book one" />
            ) : (
              <FlatList
                data={upcoming}
                keyExtractor={(a) => a.id}
                contentContainerStyle={{ padding: 16, paddingBottom: 96, width: '100%', maxWidth: ContentWidth.list, alignSelf: 'center' }}
                ItemSeparatorComponent={() => <View style={{ height: 8 }} />}
                renderItem={({ item }) => <AppointmentCard appointment={item} onPress={() => open(item)} />}
              />
            )
          ) : (
            <PastAppointmentsList
              recent={past}
              query={{ doctorId: null, patientId: me?.id ?? null }}
              emptyMessage="No past appointments"
              emptySubtitle="Your appointment history will appear here"
              renderItem={(a) => <AppointmentCard appointment={a} onPress={() => open(a)} />}
            />
          )
        }
      </AsyncView>
    </Page>
  );
}
