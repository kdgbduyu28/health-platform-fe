import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/health_repository.dart';
import '../models/profile.dart';
import '../push/browser_push.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// This browser's Web Push. Overridden in tests.
final browserPushProvider = Provider<BrowserPush>((ref) => createBrowserPush());

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  final push = ref.watch(browserPushProvider);
  late final HealthRepository repo;
  repo = HealthRepository(
    ref.watch(supabaseClientProvider),
    // Forget this browser's subscription while the session can still prove
    // whose it is, then drop it from the browser too.
    beforeSignOut: () async {
      final keys = await push.current();
      if (keys == null) return;
      await repo.deletePushSubscription(keys.endpoint);
      await push.unsubscribe();
    },
  );
  return repo;
});

/// Emits on sign-in, sign-out, and token refresh. Supabase pushes the current
/// session as soon as you subscribe, so this settles without an extra read.
final authStateChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// The signed-in user, or null. Falls back to the client's cached session so
/// the very first frame does not flash the sign-in screen for a user whose
/// session was restored from storage.
final currentUserProvider = Provider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final authState = ref.watch(authStateChangesProvider);
  return authState.value?.session?.user ?? client.auth.currentUser;
});

/// Identity of the signed-in user as a plain value. Data providers watch this
/// rather than the whole [User] so they refetch on sign-in/sign-out but not on
/// every token refresh.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentUserIdProvider) != null,
);

/// True while a password reset has verified its emailed code but not yet saved
/// the new password.
///
/// Verifying the code signs the user in, and the shell would normally swap the
/// sign-in screen for the app at that moment — before they have chosen a new
/// password. While this is set, the shell keeps the sign-in screens up.
class PasswordResetInProgress extends Notifier<bool> {
  @override
  bool build() => false;

  void start() => state = true;

  void finish() => state = false;
}

final passwordResetInProgressProvider =
    NotifierProvider<PasswordResetInProgress, bool>(PasswordResetInProgress.new);

/// The signed-in user's profile row, carrying the role that decides which
/// parts of each app are usable.
final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyProfile();
});
