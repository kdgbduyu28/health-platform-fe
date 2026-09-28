import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

import 'billing_notifications_test.dart' show FakePush;

/// Keeps notification mutes in memory, and fails on request.
class MutesRepository extends HealthRepository {
  MutesRepository() : super(SupabaseClient('http://localhost', 'test-key'));

  final muted = <String>{};
  bool failWrites = false;

  @override
  Future<Set<String>> fetchNotificationMutes(AppRole app) async => {...muted};

  @override
  Future<void> setNotificationMuted(AppRole app, String kind, bool mute) async {
    if (failWrites) throw Exception('offline');
    mute ? muted.add(kind) : muted.remove(kind);
  }
}

List<Override> _overrides(AppRole app, MutesRepository repo, AppPreferences prefs) => [
      appRoleProvider.overrideWithValue(app),
      currentUserIdProvider.overrideWithValue('u1'),
      currentUserProvider.overrideWithValue(null),
      myProfileProvider.overrideWith((ref) async => null),
      currentClinicProvider.overrideWithValue(const AsyncData(null)),
      browserPushProvider.overrideWithValue(FakePush()),
      healthRepositoryProvider.overrideWithValue(repo),
      preferencesProvider.overrideWithValue(prefs),
    ];

void main() {
  group('display preferences', () {
    test('theme follows the device until chosen, and is remembered', () {
      final prefs = AppPreferences.memory();
      final c = ProviderContainer(
          overrides: [preferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);

      expect(c.read(themeModeProvider), ThemeMode.system);
      c.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(prefs.themeMode, ThemeMode.dark);
      expect(c.read(themeModeProvider), ThemeMode.dark);
      // Back to the default stores nothing.
      c.read(themeModeProvider.notifier).set(ThemeMode.system);
      expect(prefs.getString('display.theme'), isNull);
    });

    test('the calendar view is remembered per app', () async {
      final prefs = AppPreferences.memory();
      expect(prefs.calendarView(AppRole.assistant), isNull);
      await prefs.setCalendarView(AppRole.assistant, 'day');
      expect(prefs.calendarView(AppRole.assistant), 'day');
      expect(prefs.calendarView(AppRole.admin), isNull);
    });

    test('text size is remembered, and reset puts everything back', () async {
      final prefs = AppPreferences.memory();
      await prefs.setTextSize(TextSize.larger);
      await prefs.setThemeMode(ThemeMode.light);
      await prefs.setLastClinicSlug(AppRole.patient, 'dtouchdental');
      expect(prefs.textSize, TextSize.larger);

      await prefs.resetDisplay();
      expect(prefs.textSize, TextSize.normal);
      expect(prefs.themeMode, ThemeMode.system);
      // Not a display setting: where the app opens is left alone.
      expect(prefs.lastClinicSlug(AppRole.patient), 'dtouchdental');
    });

    test('the dark theme is the clinic colour, seeded dark', () {
      expect(buildClinicTheme(null).brightness, Brightness.light);
      expect(buildClinicTheme(null, brightness: Brightness.dark).brightness,
          Brightness.dark);
    });
  });

  group('notification topics', () {
    test('every app has some, none twice', () {
      for (final app in AppRole.values) {
        final kinds = [for (final t in NotificationTopic.forApp(app)) t.kind];
        expect(kinds, isNotEmpty, reason: app.name);
        expect(kinds.toSet().length, kinds.length, reason: app.name);
      }
    });

    test('switching one off saves it; a failed save puts it back', () async {
      final repo = MutesRepository();
      final c = ProviderContainer(
          overrides: _overrides(AppRole.patient, repo, AppPreferences.memory()));
      addTearDown(c.dispose);
      final mutes = c.read(notificationMutesProvider.notifier);
      await c.read(notificationMutesProvider.future);

      await mutes.setEnabled('visit_reminder', false);
      expect(repo.muted, {'visit_reminder'});
      expect(c.read(notificationMutesProvider).value, {'visit_reminder'});

      repo.failWrites = true;
      await expectLater(mutes.setEnabled('visit_reminder', true), throwsException);
      expect(c.read(notificationMutesProvider).value, {'visit_reminder'});
    });
  });

  // Built outside the widget test: the Supabase client it wraps starts a
  // timer, which the test's fake clock would report as left pending.
  late MutesRepository widgetRepo;
  setUpAll(() => widgetRepo = MutesRepository());

  testWidgets('the settings page switches theme and topics', (tester) async {
    final repo = widgetRepo;
    final prefs = AppPreferences.memory();
    final container = ProviderContainer(
        overrides: _overrides(AppRole.doctor, repo, prefs));
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('Patient arrived'), findsOneWidget);
    // The front desk's topics are not the doctor's.
    expect(find.text('Booking requests'), findsNothing);
    // Doctors do not register patients.
    expect(find.text('Tablet PIN'), findsNothing);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(container.read(themeModeProvider), ThemeMode.dark);

    final topic = find.widgetWithText(SwitchListTile, 'Patient arrived');
    await tester.ensureVisible(topic);
    await tester.pumpAndSettle();
    await tester.tap(topic);
    await tester.pumpAndSettle();
    expect(repo.muted, {'patient_arrived'});
  });
}
