import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import '../theme/clinic_theme.dart';
import '../widgets/async_view.dart';
import '../widgets/join_clinic_screen.dart';
import '../widgets/sign_in_screen.dart';

/// The outer shell shared by all four apps.
///
/// It resolves, in order: is anyone signed in; which clinics can they use this
/// app at; which one is current. The router only mounts once there is a
/// clinic — every screen behind it assumes one, and every table is
/// deny-by-default, so without a clinic they would render full navigation over
/// uniformly empty lists.
///
/// The theme follows the current clinic, so switching clinics re-brands the
/// app in place.
class ClinicAppShell extends ConsumerWidget {
  const ClinicAppShell({
    super.key,
    required this.appName,
    required this.routerConfig,
  });

  final String appName;
  final RouterConfig<Object> routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isSignedInProvider)) {
      return MaterialApp(
        title: appName,
        theme: buildClinicTheme(null),
        debugShowCheckedModeBanner: false,
        home: SignInScreen(appName: appName),
      );
    }

    final clinicsAsync = ref.watch(myClinicsProvider);
    final clinic = ref.watch(currentClinicProvider).value;
    final theme = buildClinicTheme(clinic);

    // A refetch (after joining, switching, or a token refresh) keeps its
    // previous value, so once a clinic exists this branch holds steady rather
    // than flashing the gate below.
    if (clinic != null) {
      return MaterialApp.router(
        title: clinic.name,
        theme: theme,
        routerConfig: routerConfig,
        debugShowCheckedModeBanner: false,
      );
    }

    return MaterialApp(
      title: appName,
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: clinicsAsync.hasValue
          ? const _NoClinicYet()
          : Scaffold(
              body: AsyncView(
                value: clinicsAsync,
                onRetry: () => _refreshAccess(ref),
                builder: (_) => const SizedBox.shrink(),
              ),
            ),
    );
  }
}

void _refreshAccess(WidgetRef ref) {
  ref.invalidate(myMembershipsProvider);
  ref.invalidate(myPatientsProvider);
  ref.invalidate(visibleClinicsProvider);
}

/// Signed in, but attached to no clinic this app can be used at.
///
/// For a patient that is the normal state right after signing up, and the next
/// step is theirs: enter a clinic's code. For staff it is not something they
/// can fix themselves — access is granted by a clinic admin — so the screen
/// says exactly what to ask for.
class _NoClinicYet extends ConsumerWidget {
  const _NoClinicYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    if (app == AppRole.patient) return const JoinClinicScreen();

    final email = ref.watch(currentUserProvider)?.email ?? 'this account';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const ClinicMark(size: 72),
                  const SizedBox(height: 24),
                  Text(
                    'No clinic access yet',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You are signed in as $email, but this account is not '
                    'set up as ${_article(app)} ${app.displayName.toLowerCase()} '
                    'at any clinic.\n\n'
                    'Ask your clinic\'s administrator to add $email, then '
                    'tap Try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => _refreshAccess(ref),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(healthRepositoryProvider).signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _article(AppRole role) =>
      role == AppRole.assistant || role == AppRole.admin ? 'an' : 'a';
}
