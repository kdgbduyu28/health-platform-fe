import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_role.dart';
import '../models/clinic.dart';
import '../models/clinic_page.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../widgets/join_clinic_screen.dart';
import '../widgets/sign_in_screen.dart';
import '../widgets/staff_code_screen.dart';
import 'clinic_app_shell.dart';

/// The router every app shares, with the clinic's slug as the first segment
/// of each URL:
///
///   /                      sign in, or straight to the user's first clinic
///   /not-found             no active clinic has that slug
///   /:clinic               the public page (patient app, via [landing]);
///                          the app's home tab everywhere else
///   /:clinic/sign-in       that clinic's branded sign-in; `?next=` returns
///   /:clinic/join          patient app: join with the clinic's code
///   /:clinic/staff-code    doctor and assistant apps: request access
///   /:clinic/no-access     admin app: signed in, but not an admin here
///   /:clinic/…             [routes], relative to `/:clinic`
///
/// Who may see which of those is decided in one place, [_redirect], and
/// re-decided whenever sign-in state or the user's clinics change.
///
/// [routes] are children of `/:clinic`, so their paths are relative
/// (`'book'`, `'appointments/:id'`). A tab bar goes in a
/// [StatefulShellRoute] among them; its branches' first routes must not take
/// parameters of their own, which is why each app's home is a named tab
/// ([AppRole.homeSubpath]) rather than the bare `/:clinic`.
GoRouter createClinicRouter(
  Ref ref, {
  required String appName,
  required List<RouteBase> routes,
  GoRouterWidgetBuilder? landing,
}) {
  final app = ref.read(appRoleProvider);
  final refresh = _RouterRefresh(ref);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) =>
        _redirect(ref, state, app: app, hasLanding: landing != null),
    errorBuilder: (_, __) => const ClinicNotFoundScreen(),
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ClinicRootScreen(appName: appName),
      ),
      GoRoute(
        path: '/not-found',
        builder: (_, __) => const ClinicNotFoundScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            ClinicScope(slug: _slugOf(state.uri)!, child: child),
        routes: [
          // Two routes share the path. An exact `/:clinic` stops at the first
          // (the landing page); anything deeper falls through to the second,
          // which builds no page of its own — so the landing page never sits
          // underneath the app, where a back gesture would pop to it.
          if (landing != null) GoRoute(path: '/:clinic', builder: landing),
          GoRoute(
            path: '/:clinic',
            redirect: (_, state) => _segments(state.uri).length == 1
                ? clinicHome(_slugOf(state.uri)!, app)
                : null,
            routes: [
              GoRoute(
                path: 'sign-in',
                builder: (_, state) => SignInScreen(
                  appName: appName,
                  initialSignUp:
                      state.uri.queryParameters['mode'] == 'sign-up',
                ),
              ),
              if (app == AppRole.patient)
                GoRoute(
                  path: 'join',
                  builder: (_, __) => const JoinClinicScreen(),
                ),
              if (app.takesStaffCodes)
                GoRoute(
                  path: 'staff-code',
                  builder: (_, __) => const StaffCodeScreen(),
                ),
              if (app == AppRole.admin)
                GoRoute(
                  path: 'no-access',
                  builder: (_, __) => const NoClinicAccessScreen(),
                ),
              ...routes,
            ],
          ),
        ],
      ),
    ],
  );

  // A push notification tapped while this app is already open in a tab.
  // Only links inside the app: the payload is ours, but the check is cheap.
  ref.read(browserPushProvider).onNotificationOpened((link) {
    if (link.startsWith('/') && !link.startsWith('//')) router.go(link);
  });

  ref.onDispose(router.dispose);
  ref.onDispose(refresh.dispose);
  return router;
}

/// Where [app] lands at the clinic with [slug].
String clinicHome(String slug, AppRole app) => '/$slug${app.homeSubpath}';

/// Navigation inside the current clinic, so screens never spell out a slug.
///
///   context.goInClinic('/appointments');   // → /dtouchdental/appointments
extension ClinicNavigation on BuildContext {
  /// The slug of the clinic this screen belongs to.
  String get clinicSlug => _slugOf(GoRouterState.of(this).uri)!;

  /// [subpath] (starting with `/`) under the current clinic.
  String clinicPath(String subpath) => '/$clinicSlug$subpath';

  void goInClinic(String subpath) => go(clinicPath(subpath));

  Future<T?> pushInClinic<T extends Object?>(String subpath) =>
      push<T>(clinicPath(subpath));
}

List<String> _segments(Uri uri) =>
    [for (final s in uri.pathSegments) if (s.isNotEmpty) s];

String? _slugOf(Uri uri) {
  final segments = _segments(uri);
  return segments.isEmpty ? null : segments.first.toLowerCase();
}

/// Only paths inside this app: `?next=https://evil.example` must not turn a
/// sign-in link into an open redirect.
String? _safeNext(String? next) {
  if (next == null || !next.startsWith('/') || next.startsWith('//')) {
    return null;
  }
  return next;
}

Future<String?> _redirect(
  Ref ref,
  GoRouterState state, {
  required AppRole app,
  required bool hasLanding,
}) async {
  // A password reset signs the user in before they have chosen a new
  // password; until they have, they are still on the sign-in screens.
  final signedIn = ref.read(isSignedInProvider) &&
      !ref.read(passwordResetInProgressProvider);
  final segments = _segments(state.uri);

  // ── `/` ──
  if (segments.isEmpty) {
    if (!signedIn) return null;
    final clinics = await _myClinics(ref);
    // Nothing yet: the root screen asks for a join or staff code.
    if (clinics == null || clinics.isEmpty) return null;
    return clinicHome(clinics.first.slug, app);
  }

  final slug = segments.first.toLowerCase();
  if (slug == 'not-found') return null;
  // One spelling per clinic, so a link typed in capitals still matches.
  if (slug != segments.first) {
    return state.uri.replace(path: '/${[slug, ...segments.skip(1)].join('/')}')
        .toString();
  }
  final sub = segments.length > 1 ? segments[1] : null;

  final clinics = signedIn ? await _myClinics(ref) : const <Clinic>[];
  // The list failed to load; let the screen show that and offer a retry
  // rather than guess where to send them.
  if (clinics == null) return null;
  final isMember = clinics.any((c) => c.slug == slug);

  // Members pass even if the public page would not show (a suspended
  // clinic): deciding access is the database's job, not the URL's.
  if (!isMember) {
    final ClinicPage? page;
    try {
      page = await ref.read(clinicPageProvider(slug).future);
    } catch (_) {
      return null; // Offline, say: ClinicScope shows the error.
    }
    if (page == null) return '/not-found';
  }

  // ── Signed out ──
  if (!signedIn) {
    if (sub == 'sign-in') return null;
    if (sub == null && hasLanding) return null;
    final next = Uri.encodeComponent(state.uri.toString());
    return '/$slug/sign-in?next=$next';
  }

  // ── Signed in ──
  final home = clinicHome(slug, app);
  if (sub == 'sign-in') {
    return _safeNext(state.uri.queryParameters['next']) ?? home;
  }

  if (isMember) {
    const gates = {'join', 'staff-code', 'no-access'};
    return gates.contains(sub) ? home : null;
  }

  // Signed in at a clinic this app is not theirs at. The patient app still
  // shows the public page, which offers to join.
  if (sub == null && hasLanding) return null;
  switch (app) {
    case AppRole.patient:
      return sub == 'join' ? null : '/$slug/join';
    case AppRole.doctor:
    case AppRole.assistant:
      return sub == 'staff-code' ? null : '/$slug/staff-code';
    case AppRole.admin:
      // A branch admin has exactly one branch; any other is a wrong turn,
      // not a request for access.
      final memberships = await ref.read(myMembershipsProvider.future);
      for (final m in memberships) {
        if (!m.branchLocked) continue;
        for (final c in clinics) {
          if (c.id == m.clinicId) return clinicHome(c.slug, app);
        }
      }
      return sub == 'no-access' ? null : '/$slug/no-access';
  }
}

/// Null when the list could not be loaded.
Future<List<Clinic>?> _myClinics(Ref ref) async {
  try {
    return await ref.read(myClinicsProvider.future);
  } catch (_) {
    return null;
  }
}

/// Re-runs the redirect whenever the answer could change: signing in or out,
/// finishing a password reset, joining a clinic, being approved or removed.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(isSignedInProvider, (_, __) => notifyListeners());
    ref.listen(passwordResetInProgressProvider, (_, __) => notifyListeners());
    ref.listen(myClinicsProvider, (previous, next) {
      // Only settled lists matter; a refetch in flight changes nothing yet.
      if (next.hasValue && previous?.value != next.value) notifyListeners();
    });
  }
}
