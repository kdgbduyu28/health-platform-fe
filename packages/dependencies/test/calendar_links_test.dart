import 'package:flutter_test/flutter_test.dart';

import 'package:api_sdk/api_sdk.dart';

Appointment _visit({AppointmentStatus status = AppointmentStatus.confirmed}) =>
    Appointment(
      id: 'appt-1',
      clinicId: 'c1',
      patient: const Patient(
        id: 'chart-1',
        personId: 'person-1',
        clinicId: 'c1',
        name: 'Juan dela Cruz',
        phone: '0917',
        email: 'juan@email.com',
      ),
      doctor: const Doctor(
        id: 'd1',
        clinicId: 'c1',
        name: 'Maria Santos',
        specialty: 'General Dentistry',
        availableWeekdays: [1, 2, 3, 4, 5],
        availableTimeSlots: ['09:00'],
      ),
      dateTime: DateTime.utc(2026, 9, 29, 1),
      service: 'Root Canal',
      status: status,
      durationMinutes: 45,
    );

const _clinic = Clinic(
  id: 'c1',
  name: 'D-Touch Dental Clinic',
  slug: 'dtouchdental',
  typeSlug: 'dental',
  typeName: 'Dental',
  address: '12 Rizal St., Quezon City',
  contactPhone: '+63 2 8123 4567',
);

void main() {
  test('times are UTC basic format, whatever the device zone', () {
    expect(icsTime(DateTime.utc(2026, 9, 29, 1, 0, 5)), '20260929T010005Z');
    expect(icsTime(DateTime.utc(2026, 9, 29, 1).toLocal()), '20260929T010000Z');
  });

  test('the event names the clinic and doctor, never the service', () {
    final e = VisitEvent.fromAppointment(_visit(),
        clinic: _clinic, appLink: 'https://app.example/dtouchdental/appointments/appt-1');
    expect(e.title, 'Visit at D-Touch Dental Clinic');
    expect(e.details, contains('Dr. Maria Santos'));
    expect(e.details, contains('+63 2 8123 4567'));
    expect('${e.title}${e.details}', isNot(contains('Root Canal')));
    expect(e.end.difference(e.start), const Duration(minutes: 45));
    expect(e.uid, 'appt-1@health-platform');
  });

  test('a requested visit says so, and is tentative', () {
    final e = VisitEvent.fromAppointment(
        _visit(status: AppointmentStatus.pending), clinic: _clinic);
    expect(e.title, startsWith('Requested: '));
    expect(visitIcs(e), contains('\r\nSTATUS:TENTATIVE\r\n'));
  });

  test('Google Calendar link is filled in', () {
    final e = VisitEvent.fromAppointment(_visit(), clinic: _clinic);
    final uri = Uri.parse(googleCalendarLink(e));
    expect(uri.host, 'calendar.google.com');
    expect(uri.queryParameters['action'], 'TEMPLATE');
    expect(uri.queryParameters['text'], 'Visit at D-Touch Dental Clinic');
    expect(uri.queryParameters['dates'], '20260929T010000Z/20260929T014500Z');
    expect(uri.queryParameters['location'], '12 Rizal St., Quezon City');
  });

  test('.ics file is valid enough for every calendar', () {
    final e = VisitEvent.fromAppointment(_visit(),
        clinic: _clinic, appLink: 'https://app.example/dtouchdental/appointments/appt-1');
    final ics = visitIcs(e, now: DateTime.utc(2026, 9, 22));
    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(ics, contains('\r\nDTSTART:20260929T010000Z\r\nDTEND:20260929T014500Z\r\n'));
    expect(ics, contains(r'LOCATION:12 Rizal St.\, Quezon City'));
    expect(ics, contains('\r\nDTSTAMP:20260922T000000Z\r\n'));
    for (final line in ics.split('\r\n')) {
      expect(line.length, lessThanOrEqualTo(75), reason: line);
    }
  });

  test('text escaping and folding', () {
    expect(icsText('a,b;c\\d\ne'), r'a\,b\;c\\d\ne');
    final line = 'DESCRIPTION:${'₱' * 40}';
    final folded = foldIcsLine(line);
    expect(folded.replaceAll('\r\n ', ''), line);
    // ₱ is 3 octets in UTF-8: 12 + 21*3 = 75 on the first line.
    expect(folded.split('\r\n').first, 'DESCRIPTION:${'₱' * 21}');
  });

  test('feed links', () {
    final url = calendarFeedUrl('ab' * 32, base: 'https://x.supabase.co');
    expect(url, 'https://x.supabase.co/functions/v1/calendar-feed?token=${'ab' * 32}');
    expect(webcalUrl(url), startsWith('webcal://x.supabase.co/functions/v1/'));
    final google = Uri.parse(googleSubscribeLink(url));
    expect(google.queryParameters['cid'], webcalUrl(url));
  });
}
