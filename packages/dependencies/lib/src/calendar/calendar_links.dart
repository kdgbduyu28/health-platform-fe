import '../config/supabase_config.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/clinic.dart';

/// One visit as a calendar event, worded the way the server's calendar feed
/// words it (health-platform-be, supabase/functions/calendar-feed/ics.ts), so
/// an event added by hand and one from the feed read the same.
///
/// Deliberately thin: clinic, doctor, time and place. The service booked is
/// left out, because calendars get shared with family and work, and "Root
/// canal" on one says more than the patient chose to share.
class VisitEvent {
  const VisitEvent({
    required this.uid,
    required this.start,
    required this.end,
    required this.title,
    required this.details,
    this.location,
    this.link,
    this.tentative = false,
  });

  factory VisitEvent.fromAppointment(
    Appointment appointment, {
    Clinic? clinic,
    String? appLink,
  }) {
    final requested = appointment.status == AppointmentStatus.pending;
    final clinicName = clinic?.name ?? 'the clinic';
    return VisitEvent(
      uid: '${appointment.id}@health-platform',
      start: appointment.dateTime,
      end: appointment.endsAt,
      title: '${requested ? 'Requested: ' : ''}Visit at $clinicName',
      details: [
        'With Dr. ${appointment.doctor.name}.',
        if (requested) 'Requested: the clinic has not confirmed this time yet.',
        if (clinic?.contactPhone case final phone?) 'Clinic: $phone',
        if (appLink != null) 'Details: $appLink',
      ].join('\n'),
      location: clinic?.address,
      link: appLink,
      tentative: requested,
    );
  }

  final String uid;
  final DateTime start;
  final DateTime end;
  final String title;
  final String details;
  final String? location;
  final String? link;
  final bool tentative;
}

/// 20260929T010000Z: UTC, so the file needs no time zone block and every
/// calendar shows it on its own clock.
String icsTime(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// Google Calendar's "create event" page, filled in. Nothing is sent to
/// Google until the patient presses Save there.
String googleCalendarLink(VisitEvent e) => Uri.https(
      'calendar.google.com',
      '/calendar/render',
      {
        'action': 'TEMPLATE',
        'text': e.title,
        'dates': '${icsTime(e.start)}/${icsTime(e.end)}',
        'details': e.details,
        if (e.location != null) 'location': e.location!,
      },
    ).toString();

/// A one-event .ics file, for Apple Calendar, Outlook, and anything else.
String visitIcs(VisitEvent e, {DateTime? now}) {
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//health-platform//patient-app//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${e.uid}',
    'DTSTAMP:${icsTime(now ?? DateTime.now())}',
    'DTSTART:${icsTime(e.start)}',
    'DTEND:${icsTime(e.end)}',
    'SUMMARY:${icsText(e.title)}',
    'DESCRIPTION:${icsText(e.details)}',
    'STATUS:${e.tentative ? 'TENTATIVE' : 'CONFIRMED'}',
    if (e.location != null) 'LOCATION:${icsText(e.location!)}',
    if (e.link != null) 'URL:${e.link}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.map(foldIcsLine).join('\r\n')}\r\n';
}

/// TEXT escaping: backslash, semicolon, comma, newline.
String icsText(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r?\n'), r'\n');

/// Lines longer than 75 octets continue on the next, after a space.
String foldIcsLine(String line) {
  final out = <String>[];
  final chunk = StringBuffer();
  var size = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = rune < 0x80 ? 1 : rune < 0x800 ? 2 : rune < 0x10000 ? 3 : 4;
    if (size + n > (out.isEmpty ? 75 : 74)) {
      out.add(chunk.toString());
      chunk.clear();
      size = 0;
    }
    chunk.write(ch);
    size += n;
  }
  out.add(chunk.toString());
  return out.join('\r\n ');
}

/// The account's calendar feed, served by the calendar-feed Edge Function.
/// The token in it is the credential: whoever has the URL can read it.
String calendarFeedUrl(String token, {String base = SupabaseConfig.url}) =>
    '$base/functions/v1/calendar-feed?token=$token';

/// The same URL for calendar apps that subscribe on a webcal:// link
/// (Apple Calendar, Outlook on the desktop).
String webcalUrl(String feedUrl) =>
    feedUrl.replaceFirst(RegExp('^https?://'), 'webcal://');

/// Google Calendar's "add calendar from URL", filled in.
String googleSubscribeLink(String feedUrl) =>
    'https://calendar.google.com/calendar/render?cid='
    '${Uri.encodeComponent(webcalUrl(feedUrl))}';
