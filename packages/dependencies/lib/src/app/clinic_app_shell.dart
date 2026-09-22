import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_role.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import '../theme/clinic_theme.dart';
import '../widgets/async_view.dart';
import '../widgets/join_clinic_screen.dart';
import '../widgets/sign_in_screen.dart';
import '../widgets/staff_code_screen.dart';

/// The outer shell shared by all four apps.
///
/// The router is always mounted: the URL names the clinic, and the router's
/// redirect (see `createClinicRouter`) decides what this visitor may see
/// there. The theme follows the clinic in the URL — even signed out, from its
/// public page — so a clinic's link opens in the clinic's colours.
class ClinicAppShell extends ConsumerWidget {
  const ClinicAppShell({
    super.key,
    required this.appName,
    required this.router,
  });

  final String appName;

  /// The app's router provider. A provider rather than a value so the router
  /// can read sign-in state and clinics; it is created once and kept.
  final Provider<GoRouter> router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(routeBrandClinicProvider);
    return MaterialApp.router(
      title: clinic?.name ?? appName,
      theme: buildClinicTheme(clinic),
      routerConfig: ref.watch(router),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Wraps every page under `/:clinic`, and makes [slug] the current clinic.
///
/// The slug is copied into [routeClinicSlugProvider] after the frame rather
/// than during it (providers cannot change mid-build). Until the copy lands,
/// this shows a spinner instead of [child], so no screen ever renders against
/// the previous clinic's data.
class ClinicScope extends ConsumerStatefulWidget {
  const ClinicScope({super.key, required this.slug, required this.child});

  final String slug;
  final Widget child;

  @override
  ConsumerState<ClinicScope> createState() => _ClinicScopeState();
}

class _ClinicScopeState extends ConsumerState<ClinicScope> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ClinicScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) _sync();
  }

  void _sync() {
    final slug = widget.slug;
    Future.microtask(() {
      if (mounted) ref.read(routeClinicSlugProvider.notifier).set(slug);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(routeClinicSlugProvider) != widget.slug) {
      return const _Loading();
    }

    // The router lets a page through when it could not load what it needed
    // to decide (offline, say). Say so here, with a way to try again.
    final clinics = ref.watch(myClinicsProvider);
    if (clinics.hasError && !clinics.hasValue) {
      return Scaffold(
        body: AsyncView(
          value: clinics,
          onRetry: () => _refreshAccess(ref),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
    }
    if (ref.watch(currentClinicProvider).value == null) {
      final page = ref.watch(clinicPageProvider(widget.slug));
      if (page.hasError && !page.hasValue) {
        return Scaffold(
          body: AsyncView(
            value: page,
            onRetry: () {
              ref.invalidate(clinicPageProvider(widget.slug));
              GoRouter.of(context).refresh();
            },
            builder: (_) => const SizedBox.shrink(),
          ),
        );
      }
    }
    return widget.child;
  }
}

/// `/`: sign in, or — for an account attached to no clinic in this app — the
/// way to get attached. An account with a clinic never sees this; the router
/// sends it to that clinic.
class ClinicRootScreen extends ConsumerWidget {
  const ClinicRootScreen({super.key, required this.appName});

  final String appName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final resettingPassword = ref.watch(passwordResetInProgressProvider);
    if (!signedIn || resettingPassword) return SignInScreen(appName: appName);

    final clinics = ref.watch(myClinicsProvider);
    if (clinics.value?.isEmpty ?? false) return const _NoClinicYet();
    return Scaffold(
      body: AsyncView(
        value: clinics,
        onRetry: () => _refreshAccess(ref),
        // Clinics exist: the router is already on its way to the first.
        builder: (_) => const Center(child: CircularProgressIndicator()),
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
/// step is theirs: enter a clinic's code. A doctor or assistant enters the
/// single-use staff code their admin gave them and waits for approval. An admin
/// cannot fix it themselves — a full admin adds them — so the screen says
/// exactly what to ask for.
class _NoClinicYet extends ConsumerWidget {
  const _NoClinicYet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    if (app == AppRole.patient) return const JoinClinicScreen();
    if (app.takesStaffCodes) return const StaffCodeScreen();
    return const NoClinicAccessScreen();
  }
}

/// An admin-app account that is not an administrator here — or, at `/`,
/// anywhere.
class NoClinicAccessScreen extends ConsumerWidget {
  const NoClinicAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    final clinic = ref.watch(routeBrandClinicProvider);
    final email = ref.watch(currentUserProvider)?.email ?? 'this account';
    final role = app.displayName.toLowerCase();
    final where = clinic == null ? 'at any clinic' : 'at ${clinic.name}';

    return _MessageScreen(
      mark: ClinicMark(clinic: clinic, size: 72),
      title: 'No clinic access yet',
      body: 'You are signed in as $email, but this account is not set up as '
          '${_article(app)} $role $where.\n\n'
          'Ask the clinic\'s administrator to add $email, then tap Try again.',
      actions: [
        FilledButton.icon(
          onPressed: () => _refreshAccess(ref),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => ref.read(healthRepositoryProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  static String _article(AppRole role) =>
      role == AppRole.assistant || role == AppRole.admin ? 'an' : 'a';
}

/// `/not-found`: no active clinic has the slug that was asked for. A
/// suspended clinic lands here too, on purpose — it looks like a typo.
class ClinicNotFoundScreen extends StatelessWidget {
  const ClinicNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _MessageScreen(
      mark: const ClinicMark(size: 72),
      title: 'Clinic not found',
      body: 'There is no clinic at this address. Check the link your clinic '
          'sent you, or ask them for it again.',
      actions: [
        FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go to start'),
        ),
      ],
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.mark,
    required this.title,
    required this.body,
    required this.actions,
  });

  final Widget mark;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  mark,
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
