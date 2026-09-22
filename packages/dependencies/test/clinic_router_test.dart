import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:api_sdk/api_sdk.dart';

// Drives the real shared router — redirect, refresh, ClinicScope — with the
// network-backed providers replaced by fixed data.

const dtouch = Clinic(
  id: 'dt',
  name: 'D-Touch Dental Clinic',
  slug: 'dtouchdental',
  typeSlug: 'dental',
  typeName: 'Dental',
);
const other = Clinic(
  id: 'ot',
  name: 'BrightSmile Dental Studio',
  slug: 'brightsmile',
  typeSlug: 'dental',
  typeName: 'Dental',
);
final publicPages = {
  for (final c in [dtouch, other]) c.slug: ClinicPage(clinic: c),
};

/// Who is signed in: flip it mid-test to sign in or out.
class FakeUser extends Notifier<String?> {
  FakeUser(this.initial);
  final String? initial;

  @override
  String? build() => initial;

  void set(String? id) => state = id;
}

late NotifierProvider<FakeUser, String?> fakeUserProvider;

/// Every app's routes look like this: a tab bar whose first tab is the
/// app's home, plus one page outside it.
Provider<GoRouter> routerFor(AppRole app, {required bool landing}) =>
    Provider<GoRouter>((ref) => createClinicRouter(
          ref,
          appName: 'Test',
          landing: landing ? (_, __) => const Text('LANDING') : null,
          routes: [
            GoRoute(path: 'book', builder: (_, __) => const Text('BOOK')),
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) => Scaffold(
                body: shell,
                bottomNavigationBar: TextButton(
                  onPressed: () => shell.goBranch(1),
                  child: const Text('SECOND TAB'),
                ),
              ),
              branches: [
                StatefulShellBranch(routes: [
                  GoRoute(
                    path: app.homeSubpath.substring(1),
                    builder: (_, __) => const Text('HOME'),
                  ),
                ]),
                StatefulShellBranch(routes: [
                  GoRoute(
                    path: 'patients',
                    builder: (_, __) => const Text('PATIENTS'),
                  ),
                ]),
              ],
            ),
          ],
        ));

class Harness {
  Harness(this.tester, this.container, this.router);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Redirects are async and ClinicScope syncs after a frame, so pump a few;
  /// then let the page transition finish, or the outgoing page is still on
  /// screen. (Not pumpAndSettle: a loading spinner never settles.)
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<String> go(String location) async {
    router.go(location);
    await settle();
    return this.location;
  }

  Future<void> signIn() async {
    container.read(fakeUserProvider.notifier).set('u1');
    await settle();
  }

  Future<void> signOut() async {
    container.read(fakeUserProvider.notifier).set(null);
    await settle();
  }
}

Future<Harness> pumpApp(
  WidgetTester tester, {
  required AppRole app,
  bool signedIn = false,
  List<Clinic> visible = const [],
  List<Patient> charts = const [],
  List<ClinicMembership> memberships = const [],
}) async {
  fakeUserProvider = NotifierProvider<FakeUser, String?>(
      () => FakeUser(signedIn ? 'u1' : null));
  final routerProvider = routerFor(app, landing: app == AppRole.patient);

  final container = ProviderContainer(overrides: [
    appRoleProvider.overrideWithValue(app),
    currentUserProvider.overrideWithValue(null),
    currentUserIdProvider.overrideWith((ref) => ref.watch(fakeUserProvider)),
    visibleClinicsProvider.overrideWith((ref) async => visible),
    myPatientsProvider.overrideWith((ref) async => charts),
    myMembershipsProvider.overrideWith((ref) async => memberships),
    myStaffRequestsProvider.overrideWith((ref) async => const []),
    clinicPageProvider.overrideWith((ref, slug) async => publicPages[slug]),
  ]);
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  final harness = Harness(tester, container, router);
  await harness.settle();
  return harness;
}

Patient chartAt(String clinicId) => Patient(
      id: 'chart-$clinicId',
      personId: 'person-1',
      clinicId: clinicId,
      name: 'Juan dela Cruz',
      phone: '0917',
      email: '',
    );

ClinicMembership staffAt(String clinicId, AppRole role,
        {bool branchLocked = false}) =>
    ClinicMembership(
      profileId: 'u1',
      clinicId: clinicId,
      role: role,
      branchLocked: branchLocked,
    );

void main() {
  group('signed out, patient app', () {
    testWidgets('/dtouchdental is the public landing page', (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/dtouchdental'), '/dtouchdental');
      expect(find.text('LANDING'), findsOneWidget);
    });

    testWidgets('…which makes the clinic current and brands the app',
        (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      await h.go('/dtouchdental');
      expect(h.container.read(routeClinicSlugProvider), 'dtouchdental');
      expect(h.container.read(routeBrandClinicProvider)?.name,
          'D-Touch Dental Clinic');
    });

    testWidgets('anything deeper asks them to sign in, then comes back',
        (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/dtouchdental/book'),
          '/dtouchdental/sign-in?next=%2Fdtouchdental%2Fbook');
      expect(find.text('Sign in to D-Touch Dental Clinic'), findsOneWidget);
    });

    testWidgets('an unknown clinic is not found', (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/no-such-clinic'), '/not-found');
      expect(find.text('Clinic not found'), findsOneWidget);
    });

    testWidgets('a slug typed in capitals still opens the clinic',
        (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/DTouchDental'), '/dtouchdental');
    });

    testWidgets('/ is the unbranded sign-in', (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/'), '/');
      expect(find.text('Sign in to your clinic'), findsOneWidget);
    });
  });

  group('signed in, patient app', () {
    testWidgets('/ opens their clinic', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      expect(await h.go('/'), '/dtouchdental/home');
      expect(find.text('HOME'), findsOneWidget);
      expect(h.container.read(currentClinicIdProvider), 'dt');
    });

    testWidgets('signing in follows ?next=', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient, visible: [dtouch], charts: [chartAt('dt')]);
      await h.go('/dtouchdental/book');
      await h.signIn();
      expect(h.location, '/dtouchdental/book');
      expect(find.text('BOOK'), findsOneWidget);
    });

    testWidgets('?next= cannot leave the app', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      expect(await h.go('/dtouchdental/sign-in?next=//evil.example'),
          '/dtouchdental/home');
    });

    testWidgets('signing out returns to that clinic\'s sign-in',
        (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      await h.go('/dtouchdental/home');
      await h.signOut();
      expect(h.location, '/dtouchdental/sign-in?next=%2Fdtouchdental%2Fhome');
    });

    testWidgets('members still see the public page', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      expect(await h.go('/dtouchdental'), '/dtouchdental');
    });

    testWidgets('at a clinic they have not joined, the app asks for its code',
        (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      expect(await h.go('/brightsmile/book'), '/brightsmile/join');
      expect(find.text('Join BrightSmile Dental Studio'), findsOneWidget);
      // …but the public page is still theirs to read.
      expect(await h.go('/brightsmile'), '/brightsmile');
    });

    testWidgets('a member has no business on the join screen', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.patient,
          signedIn: true,
          visible: [dtouch],
          charts: [chartAt('dt')]);
      expect(await h.go('/dtouchdental/join'), '/dtouchdental/home');
    });

    testWidgets('no clinic yet: / asks for a code', (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient, signedIn: true);
      expect(await h.go('/'), '/');
      expect(find.text('Join your clinic'), findsOneWidget);
    });
  });

  group('staff apps', () {
    testWidgets('signed out, the clinic link is its sign-in (no landing page)',
        (tester) async {
      final h = await pumpApp(tester, app: AppRole.doctor);
      expect(await h.go('/dtouchdental'),
          '/dtouchdental/sign-in?next=%2Fdtouchdental');
    });

    testWidgets('/:clinic opens the app\'s home tab', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.doctor,
          signedIn: true,
          visible: [dtouch],
          memberships: [staffAt('dt', AppRole.doctor)]);
      expect(await h.go('/dtouchdental'), '/dtouchdental/schedule');
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('a tab never visited opens under the same clinic',
        (tester) async {
      // go_router fills the branch's `/:clinic` from the current URL. If it
      // could not, this would assert (debug) or 404.
      final h = await pumpApp(tester,
          app: AppRole.doctor,
          signedIn: true,
          visible: [dtouch],
          memberships: [staffAt('dt', AppRole.doctor)]);
      await h.go('/dtouchdental/schedule');
      await tester.tap(find.text('SECOND TAB'));
      await h.settle();
      expect(h.location, '/dtouchdental/patients');
      expect(find.text('PATIENTS'), findsOneWidget);
    });

    testWidgets('a doctor at another clinic is offered the staff code',
        (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.doctor,
          signedIn: true,
          visible: [dtouch, other],
          memberships: [staffAt('dt', AppRole.doctor)]);
      expect(await h.go('/brightsmile/schedule'), '/brightsmile/staff-code');
    });

    testWidgets('the front desk lands on check-in', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.assistant,
          signedIn: true,
          visible: [dtouch],
          memberships: [staffAt('dt', AppRole.assistant)]);
      expect(await h.go('/'), '/dtouchdental/check-in');
    });
  });

  group('admin app', () {
    testWidgets('a full admin at a clinic that is not theirs has no access',
        (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.admin,
          signedIn: true,
          visible: [dtouch, other],
          memberships: [staffAt('dt', AppRole.admin)]);
      expect(await h.go('/brightsmile/dashboard'), '/brightsmile/no-access');
      expect(find.text('No clinic access yet'), findsOneWidget);
    });

    testWidgets('a branch admin is always returned to their branch',
        (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.admin,
          signedIn: true,
          visible: [dtouch, other],
          memberships: [staffAt('dt', AppRole.admin, branchLocked: true)]);
      expect(await h.go('/brightsmile/settings'), '/dtouchdental/dashboard');
      expect(h.container.read(currentClinicIdProvider), 'dt');
    });

    testWidgets('a full admin of two branches switches by URL', (tester) async {
      final h = await pumpApp(tester,
          app: AppRole.admin,
          signedIn: true,
          visible: [dtouch, other],
          memberships: [
            staffAt('dt', AppRole.admin),
            staffAt('ot', AppRole.admin),
          ]);
      expect(await h.go('/brightsmile'), '/brightsmile/dashboard');
      expect(h.container.read(currentClinicIdProvider), 'ot');
      expect(await h.go('/dtouchdental/dashboard'), '/dtouchdental/dashboard');
      expect(h.container.read(currentClinicIdProvider), 'dt');
    });
  });
}
