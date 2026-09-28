import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../models/app_notification.dart';
import '../models/app_role.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// This app's inbox for the signed-in account, newest first, kept live over
/// Realtime.
final notificationsProvider =
    StreamProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserIdProvider);
  final app = ref.watch(appRoleProvider);
  return ref
      .watch(healthRepositoryProvider)
      .watchNotifications(app)
      .map((list) => list.reversed.toList());
});

final unreadNotificationsProvider = Provider<int>((ref) =>
    (ref.watch(notificationsProvider).value ?? const [])
        .where((n) => !n.isRead)
        .length);

/// Where this browser stands on push notifications for this app.
enum PushState {
  /// The browser has no Push API.
  unsupported,

  /// iPhone or iPad Safari: push works once the site is on the home screen.
  needsHomeScreen,

  /// The person blocked notifications for this site; only browser settings
  /// can undo that.
  blocked,
  off,
  on,
}

class PushSettings extends AsyncNotifier<PushState> {
  @override
  Future<PushState> build() async {
    final userId = ref.watch(currentUserIdProvider);
    final push = ref.watch(browserPushProvider);
    if (!push.supported) {
      return push.needsHomeScreenInstall
          ? PushState.needsHomeScreen
          : PushState.unsupported;
    }
    if (push.permission == 'denied') return PushState.blocked;
    final keys = await push.current();
    if (keys == null || userId == null) return PushState.off;
    // Re-register on every start: it costs one call, and heals a row lost
    // to an expired subscription or a sign-in by someone else.
    await _save(keys.endpoint, keys.p256dh, keys.auth);
    return PushState.on;
  }

  Future<void> _save(String endpoint, String p256dh, String auth) =>
      ref.read(healthRepositoryProvider).savePushSubscription(
            app: ref.read(appRoleProvider),
            endpoint: endpoint,
            p256dh: p256dh,
            auth: auth,
            userAgent: ref.read(browserPushProvider).userAgent,
          );

  /// Asks the browser, subscribes, and registers the subscription.
  Future<void> enable() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final push = ref.read(browserPushProvider);
      final keys = await push.subscribe(SupabaseConfig.vapidPublicKey);
      if (keys == null) {
        return push.permission == 'denied' ? PushState.blocked : PushState.off;
      }
      await _save(keys.endpoint, keys.p256dh, keys.auth);
      return PushState.on;
    });
  }

  Future<void> disable() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final push = ref.read(browserPushProvider);
      final keys = await push.current();
      if (keys != null) {
        await ref.read(healthRepositoryProvider).deletePushSubscription(keys.endpoint);
      }
      await push.unsubscribe();
      return PushState.off;
    });
  }
}

final pushSettingsProvider =
    AsyncNotifierProvider<PushSettings, PushState>(PushSettings.new);

/// A kind of notification someone can switch off in Settings. The kinds are
/// the database's (`notification_mutes.kind`); the words are ours.
class NotificationTopic {
  const NotificationTopic(this.kind, this.label, this.description);

  final String kind;
  final String label;
  final String description;

  /// What [app] can be told about, in the order Settings lists them. Mirrors
  /// who hears what in 20260924120200_notifications.
  static List<NotificationTopic> forApp(AppRole app) => switch (app) {
        AppRole.patient => const [
            NotificationTopic('visit_reminder', 'Visit reminders',
                'The day before a confirmed visit'),
            NotificationTopic('visit_confirmed', 'Visit confirmed',
                'When the clinic confirms a booking'),
            NotificationTopic('visit_moved', 'Visit moved',
                'When the clinic changes the time'),
            NotificationTopic('visit_cancelled', 'Visit cancelled',
                'When the clinic cancels a visit'),
            NotificationTopic('patient_note', 'Notes from your doctor',
                'Advice written after a visit'),
            NotificationTopic('invoice_issued', 'Bills',
                'When a new bill is ready'),
          ],
        AppRole.assistant || AppRole.admin => const [
            NotificationTopic('booking_requested', 'Booking requests',
                'A patient asks for a visit'),
            NotificationTopic('visit_moved', 'Reschedule requests',
                'A patient asks to move a visit'),
            NotificationTopic('visit_cancelled', 'Cancellations',
                'A patient cancels a visit'),
          ],
        AppRole.doctor => const [
            NotificationTopic('patient_arrived', 'Patient arrived',
                'Your patient is checked in and waiting'),
          ],
      };
}

/// The kinds switched off in this app for the signed-in account.
class NotificationMutes extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() {
    ref.watch(currentUserIdProvider);
    return ref
        .watch(healthRepositoryProvider)
        .fetchNotificationMutes(ref.watch(appRoleProvider));
  }

  /// Flips [kind] on screen at once, and back if the save fails.
  Future<void> setEnabled(String kind, bool enabled) async {
    final before = state.value ?? const <String>{};
    state = AsyncData(enabled ? ({...before}..remove(kind)) : {...before, kind});
    try {
      await ref
          .read(healthRepositoryProvider)
          .setNotificationMuted(ref.read(appRoleProvider), kind, !enabled);
    } catch (e, st) {
      state = AsyncData(before);
      Error.throwWithStackTrace(e, st);
    }
  }
}

final notificationMutesProvider =
    AsyncNotifierProvider<NotificationMutes, Set<String>>(
        NotificationMutes.new);
