import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';
import '../models/dental_chart.dart';
import 'clinic_provider.dart';

/// Small things this device remembers between visits: which clinic was open
/// last, the email last signed in with, how teeth are numbered, light or dark.
///
/// Nothing here is private or authoritative. On the web it is localStorage,
/// which the user can clear at any time, so every reader has a sensible
/// default and nothing breaks when it is empty.
class AppPreferences {
  AppPreferences(SharedPreferences prefs) : _prefs = prefs;

  /// Remembers for as long as the app runs. Used when storage is unavailable
  /// (a locked-down browser) and in tests.
  AppPreferences.memory() : _prefs = null;

  final SharedPreferences? _prefs;
  final _memory = <String, String>{};

  /// Loaded once in `initializeHealthPlatform`; in memory until then.
  static AppPreferences shared = AppPreferences.memory();

  static Future<AppPreferences> load() async {
    try {
      return AppPreferences(await SharedPreferences.getInstance());
    } catch (_) {
      return AppPreferences.memory();
    }
  }

  String? getString(String key) => _prefs?.getString(key) ?? _memory[key];

  Future<void> setString(String key, String? value) async {
    if (value == null) {
      _memory.remove(key);
      await _prefs?.remove(key);
    } else {
      _memory[key] = value;
      await _prefs?.setString(key, value);
    }
  }

  // ── Keys ─────────────────────────────────────────────────────────────────

  /// The clinic this app last showed. Per app: the same browser may run the
  /// doctor app at one clinic and the patient app at another.
  String? lastClinicSlug(AppRole app) => getString('last_clinic.${app.wire}');

  Future<void> setLastClinicSlug(AppRole app, String slug) =>
      setString('last_clinic.${app.wire}', slug);

  String? get lastEmail => getString('auth.last_email');

  Future<void> setLastEmail(String? email) =>
      setString('auth.last_email', email);

  /// The front desk tablet's hand-off in progress, as JSON (see
  /// `KioskSession`). Kept so a reload mid-form still lands on the form, not
  /// on the clinic's patient list.
  String? kioskSession(AppRole app) => getString('kiosk.${app.wire}');

  Future<void> setKioskSession(AppRole app, String? json) =>
      setString('kiosk.${app.wire}', json);

  ToothNumbering get toothNumbering =>
      ToothNumbering.fromWire(getString('dental.numbering'));

  Future<void> setToothNumbering(ToothNumbering n) =>
      setString('dental.numbering', n.wire);

  /// Light, dark, or whatever the device is set to (the default). One for
  /// all four apps: it is how this device should look, not a per-app choice.
  ThemeMode get themeMode => ThemeMode.values.firstWhere(
        (m) => m.name == getString('display.theme'),
        orElse: () => ThemeMode.system,
      );

  Future<void> setThemeMode(ThemeMode mode) => setString(
      'display.theme', mode == ThemeMode.system ? null : mode.name);

  TextSize get textSize => TextSize.values.firstWhere(
        (s) => s.name == getString('display.text_size'),
        orElse: () => TextSize.normal,
      );

  Future<void> setTextSize(TextSize size) => setString(
      'display.text_size', size == TextSize.normal ? null : size.name);

  /// How this app lays out a day's visits: a list, or a board by status.
  /// Per app, like the clinic: a doctor may like the board while the front
  /// desk on the same browser keeps the list.
  AppointmentView appointmentView(AppRole app) =>
      AppointmentView.values.firstWhere(
        (v) => v.name == getString('appointments.view.${app.wire}'),
        orElse: () => AppointmentView.list,
      );

  Future<void> setAppointmentView(AppRole app, AppointmentView view) =>
      setString('appointments.view.${app.wire}',
          view == AppointmentView.list ? null : view.name);

  /// The calendar's last month / week / day, by name; null until one is
  /// picked, when the calendar goes by the screen's width.
  String? calendarView(AppRole app) => getString('calendar.view.${app.wire}');

  Future<void> setCalendarView(AppRole app, String view) =>
      setString('calendar.view.${app.wire}', view);

  /// Forgets everything above except the clinic and the tablet hand-off,
  /// which are not preferences: dropping a kiosk session here would hand the
  /// app back to whoever holds the tablet.
  Future<void> resetDisplay() async {
    await setString('display.theme', null);
    await setString('display.text_size', null);
    await setString('dental.numbering', null);
  }
}

/// Text larger than the device's own setting, for reading at arm's length —
/// a front desk tablet, or a patient without their glasses. It multiplies
/// the device's setting rather than replacing it.
enum TextSize {
  normal(1.0, 'Default'),
  large(1.15, 'Large'),
  larger(1.3, 'Larger');

  const TextSize(this.scale, this.label);

  final double scale;
  final String label;
}

/// A day's visits as cards in time order, or as columns by where each visit
/// stands (see `AppointmentBoard`).
enum AppointmentView { list, board }

class AppointmentViewNotifier extends Notifier<AppointmentView> {
  @override
  AppointmentView build() => ref
      .watch(preferencesProvider)
      .appointmentView(ref.watch(appRoleProvider));

  void set(AppointmentView view) {
    state = view;
    ref
        .read(preferencesProvider)
        .setAppointmentView(ref.read(appRoleProvider), view);
  }
}

final appointmentViewProvider =
    NotifierProvider<AppointmentViewNotifier, AppointmentView>(
        AppointmentViewNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(preferencesProvider).themeMode;

  void set(ThemeMode mode) {
    state = mode;
    ref.read(preferencesProvider).setThemeMode(mode);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class TextSizeNotifier extends Notifier<TextSize> {
  @override
  TextSize build() => ref.watch(preferencesProvider).textSize;

  void set(TextSize size) {
    state = size;
    ref.read(preferencesProvider).setTextSize(size);
  }
}

final textSizeProvider =
    NotifierProvider<TextSizeNotifier, TextSize>(TextSizeNotifier.new);

final preferencesProvider =
    Provider<AppPreferences>((ref) => AppPreferences.shared);

/// How the dental chart numbers teeth on this device.
class ToothNumberingNotifier extends Notifier<ToothNumbering> {
  @override
  ToothNumbering build() => ref.watch(preferencesProvider).toothNumbering;

  void set(ToothNumbering numbering) {
    state = numbering;
    ref.read(preferencesProvider).setToothNumbering(numbering);
  }
}

final toothNumberingProvider =
    NotifierProvider<ToothNumberingNotifier, ToothNumbering>(
        ToothNumberingNotifier.new);
