import { SupabaseConfig } from '../config/supabase_config';
import type { Appointment } from '../models/appointment';
import type { Clinic } from '../models/clinic';

/// One visit as a calendar event, worded the way the server's calendar feed
/// words it (health-platform-be, supabase/functions/calendar-feed/ics.ts), so
/// an event added by hand and one from the feed read the same.
///
/// Deliberately thin: clinic, doctor, time and place. The service booked is
/// left out, because calendars get shared with family and work, and "Root
/// canal" on one says more than the patient chose to share.
export type VisitEvent = {
  uid: string;
  start: Date;
  end: Date;
  title: string;
  details: string;
  location: string | null;
  link: string | null;
  tentative: boolean;
};

export function visitEventFromAppointment(
  appointment: Appointment,
  opts: { clinic?: Clinic | null; appLink?: string | null } = {},
): VisitEvent {
  const requested = appointment.status === 'pending';
  const clinic = opts.clinic ?? null;
  const clinicName = clinic?.name ?? 'the clinic';
  const appLink = opts.appLink ?? null;
  return {
    uid: `${appointment.id}@health-platform`,
    start: appointment.dateTime,
    end: appointment.endsAt,
    title: `${requested ? 'Requested: ' : ''}Visit at ${clinicName}`,
    details: [
      `With Dr. ${appointment.doctor.name}.`,
      ...(requested ? ['Requested: the clinic has not confirmed this time yet.'] : []),
      ...(clinic?.contactPhone != null ? [`Clinic: ${clinic.contactPhone}`] : []),
      ...(appLink != null ? [`Details: ${appLink}`] : []),
    ].join('\n'),
    location: clinic?.address ?? null,
    link: appLink,
    tentative: requested,
  };
}

/// 20260929T010000Z: UTC, so the file needs no time zone block and every
/// calendar shows it on its own clock.
export function icsTime(t: Date): string {
  const two = (n: number) => String(n).padStart(2, '0');
  return (
    `${String(t.getUTCFullYear()).padStart(4, '0')}${two(t.getUTCMonth() + 1)}${two(t.getUTCDate())}` +
    `T${two(t.getUTCHours())}${two(t.getUTCMinutes())}${two(t.getUTCSeconds())}Z`
  );
}

/// Google Calendar's "create event" page, filled in. Nothing is sent to
/// Google until the patient presses Save there.
export function googleCalendarLink(e: VisitEvent): string {
  const params = new URLSearchParams({
    action: 'TEMPLATE',
    text: e.title,
    dates: `${icsTime(e.start)}/${icsTime(e.end)}`,
    details: e.details,
  });
  if (e.location != null) params.set('location', e.location);
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/// A one-event .ics file, for Apple Calendar, Outlook, and anything else.
export function visitIcs(e: VisitEvent, now: Date = new Date()): string {
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//health-platform//patient-app//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${e.uid}`,
    `DTSTAMP:${icsTime(now)}`,
    `DTSTART:${icsTime(e.start)}`,
    `DTEND:${icsTime(e.end)}`,
    `SUMMARY:${icsText(e.title)}`,
    `DESCRIPTION:${icsText(e.details)}`,
    `STATUS:${e.tentative ? 'TENTATIVE' : 'CONFIRMED'}`,
    ...(e.location != null ? [`LOCATION:${icsText(e.location)}`] : []),
    ...(e.link != null ? [`URL:${e.link}`] : []),
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return `${lines.map(foldIcsLine).join('\r\n')}\r\n`;
}

/// TEXT escaping: backslash, semicolon, comma, newline.
export function icsText(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
}

/// Lines longer than 75 octets continue on the next, after a space.
export function foldIcsLine(line: string): string {
  const out: string[] = [];
  let chunk = '';
  let size = 0;
  for (const ch of line) {
    const cp = ch.codePointAt(0)!;
    const n = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    if (size + n > (out.length === 0 ? 75 : 74)) {
      out.push(chunk);
      chunk = '';
      size = 0;
    }
    chunk += ch;
    size += n;
  }
  out.push(chunk);
  return out.join('\r\n ');
}

/// The account's calendar feed, served by the calendar-feed Edge Function.
/// The token in it is the credential: whoever has the URL can read it.
export function calendarFeedUrl(token: string, base: string = SupabaseConfig.url): string {
  return `${base}/functions/v1/calendar-feed?token=${token}`;
}

/// The same URL for calendar apps that subscribe on a webcal:// link (Apple
/// Calendar, Outlook on the desktop).
export function webcalUrl(feedUrl: string): string {
  return feedUrl.replace(/^https?:\/\//, 'webcal://');
}

/// Google Calendar's "add calendar from URL", filled in.
export function googleSubscribeLink(feedUrl: string): string {
  return `https://calendar.google.com/calendar/render?cid=${encodeURIComponent(webcalUrl(feedUrl))}`;
}
