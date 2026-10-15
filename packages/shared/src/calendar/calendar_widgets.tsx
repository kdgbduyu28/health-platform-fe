import { View } from 'react-native';
import { ActivityIndicator, Button, Text } from 'react-native-paper';

import type { Appointment } from '../models/appointment';
import { appOrigin, copyText, downloadTextFile, openExternal } from '../platform/browser';
import { useClinicById } from '../queries/clinic';
import { useCalendarFeedUrl, useResetCalendarFeed } from '../queries/misc';
import { useAppTheme } from '../theme/clinic_theme';
import { describeError } from '../ui/async_view';
import { Icon } from '../ui/icon';
import { ListTile } from '../ui/kit';
import { type Close, SheetScroll, useOverlay } from '../ui/overlay';
import { googleCalendarLink, googleSubscribeLink, visitEventFromAppointment, visitIcs, webcalUrl } from './calendar_links';

/// "Add to calendar" for one upcoming visit: a Google Calendar link or an
/// .ics file, both made on the device. It does not follow a later move; the
/// sheet offers the feed, which does.
export function AddToCalendarButton({ appointment }: { appointment: Appointment }) {
  const overlay = useOverlay();
  const clinic = useClinicById(appointment.clinicId);
  const openFeed = useCalendarFeedSheet();
  const open = () => {
    const origin = appOrigin();
    const event = visitEventFromAppointment(appointment, {
      clinic,
      appLink: origin == null || clinic == null ? null : `${origin}/${clinic.slug}/appointments/${appointment.id}`,
    });
    void overlay.showSheet((close: Close<void>) => (
      <View style={{ paddingBottom: 16 }}>
        <ListTile
          leading={<Icon name="calendar-month" />}
          title="Google Calendar"
          subtitle="Opens Google Calendar to save it"
          onPress={() => {
            close();
            openExternal(googleCalendarLink(event));
          }}
        />
        <ListTile
          leading={<Icon name="download" />}
          title="Apple Calendar, Outlook, others"
          subtitle="Downloads an .ics file to open"
          onPress={() => {
            close();
            downloadTextFile('visit.ics', 'text/calendar', visitIcs(event));
          }}
        />
        <ListTile
          leading={<Icon name="sync" />}
          title="Keep all my visits in my calendar"
          subtitle="Subscribe once; moved and cancelled visits update on their own"
          onPress={() => {
            close();
            openFeed();
          }}
        />
      </View>
    ));
  };
  return (
    <Button mode="outlined" icon="event-available" onPress={open}>
      Add to calendar
    </Button>
  );
}

/// Subscribing a calendar app to the account's feed, and resetting its URL.
export function useCalendarFeedSheet(): () => void {
  const overlay = useOverlay();
  return () => void overlay.showSheet(() => <CalendarFeedSheet />);
}

function CalendarFeedSheet() {
  const { colors } = useAppTheme();
  const overlay = useOverlay();
  const url = useCalendarFeedUrl();
  const reset = useResetCalendarFeed();

  const confirmReset = async () => {
    const ok = await overlay.confirm({
      title: 'Reset calendar link?',
      message: 'The old link stops working at once. Any calendar subscribed to it stops updating; subscribe again with the new one.',
      cancelLabel: 'Keep',
      confirmLabel: 'Reset',
    });
    if (!ok) return;
    try {
      await reset();
    } catch (e) {
      overlay.snack(describeError(e));
    }
  };

  return (
    <SheetScroll padding={24}>
      <Text variant="titleLarge">Your visits in your calendar</Text>
      <Text style={{ marginTop: 8, color: colors.onSurfaceVariant }}>
        Subscribe once and every visit, at every clinic you belong to, appears in your calendar. Moved and cancelled visits update on
        their own. Google Calendar checks for changes every few hours.
      </Text>
      <View style={{ height: 16 }} />
      {url.hasValue && url.value != null ? (
        <View style={{ gap: 8 }}>
          <Button mode="contained" icon="calendar-month" onPress={() => openExternal(googleSubscribeLink(url.value!))}>
            Add to Google Calendar
          </Button>
          <Button mode="outlined" icon="event" onPress={() => openExternal(webcalUrl(url.value!))}>
            Apple Calendar or Outlook
          </Button>
          <Button
            mode="outlined"
            icon="link"
            onPress={async () => overlay.snack((await copyText(url.value!)) ? 'Link copied' : 'Could not copy the link')}
          >
            Copy link for another app
          </Button>
          <Text variant="bodySmall" style={{ marginTop: 8, color: colors.onSurfaceVariant }}>
            Anyone with this link can see your visit times, so keep it to yourself. Visits show the clinic and doctor, not what they are
            for.
          </Text>
          <Button style={{ alignSelf: 'flex-start' }} onPress={() => void confirmReset()}>
            Reset link
          </Button>
        </View>
      ) : url.hasError ? (
        <Text style={{ color: colors.error }}>{describeError(url.error)}</Text>
      ) : (
        <View style={{ padding: 16, alignItems: 'center' }}>
          <ActivityIndicator />
        </View>
      )}
    </SheetScroll>
  );
}
