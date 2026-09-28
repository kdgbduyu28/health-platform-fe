import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:api_sdk/api_sdk.dart';

// The tabs as a phone, a tablet and a desktop see them, on a tab page and on
// a page opened from one — with the same shape as the apps' routers.

List<ClinicTab> _tabs(WidgetRef ref) => const [
      ClinicTab(
        path: '/schedule',
        label: 'Schedule',
        icon: Icons.today_outlined,
        selectedIcon: Icons.today,
      ),
      ClinicTab(
        path: '/patients',
        label: 'Patients',
        icon: Icons.group_outlined,
        selectedIcon: Icons.group,
      ),
    ];

Widget _page(BuildContext context, String title, [String? link]) => Scaffold(
      body: Column(children: [
        Text(title),
        Builder(
          builder: (context) => Text(ClinicNavScaffold.showsClinicName(context)
              ? 'RAIL NAMES CLINIC'
              : 'PAGE NAMES CLINIC'),
        ),
        if (link != null)
          TextButton(
            onPressed: () => context.pushInClinic(link),
            child: const Text('open'),
          ),
      ]),
    );

GoRouter _router() => GoRouter(
      initialLocation: '/dt/patients',
      routes: [
        GoRoute(
          path: '/:clinic',
          redirect: (_, __) => null,
          routes: [
            GoRoute(
              path: 'patients/:id',
              builder: (context, _) => ClinicNavScaffold.frame(
                tabs: _tabs,
                child: _page(context, 'HISTORY'),
              ),
            ),
            StatefulShellRoute.indexedStack(
              builder: (_, __, shell) =>
                  ClinicNavScaffold.shell(tabs: _tabs, shell: shell),
              branches: [
                StatefulShellBranch(routes: [
                  GoRoute(
                    path: 'schedule',
                    builder: (context, _) => _page(context, 'SCHEDULE'),
                  ),
                ]),
                StatefulShellBranch(routes: [
                  GoRoute(
                    path: 'patients',
                    builder: (context, _) =>
                        _page(context, 'PATIENTS', '/patients/p1'),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ],
    );

Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [routeBrandClinicProvider.overrideWithValue(null)],
    child: MaterialApp.router(
      theme: buildClinicTheme(null),
      routerConfig: _router(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openPatient(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.text('HISTORY'), findsOneWidget);
}

void main() {
  testWidgets('only beside a desktop rail does a page leave the clinic out',
      (tester) async {
    await _pumpAt(tester, 400);
    expect(find.text('PAGE NAMES CLINIC'), findsOneWidget);
    await _pumpAt(tester, 900);
    expect(find.text('PAGE NAMES CLINIC'), findsOneWidget);
    await _pumpAt(tester, 1400);
    expect(find.text('RAIL NAMES CLINIC'), findsOneWidget);
    // A page opened from a tab keeps the rail, and the same title rule.
    await _openPatient(tester);
    expect(find.text('RAIL NAMES CLINIC'), findsOneWidget);
  });

  testWidgets('a phone has a bottom bar, and a patient page covers it',
      (tester) async {
    await _pumpAt(tester, 400);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await _openPatient(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a tablet has a rail that stays beside a patient page',
      (tester) async {
    await _pumpAt(tester, 900);
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.selectedIndex, 1);

    await _openPatient(tester);
    // The page's own rail, with its tab lit.
    final framed =
        tester.widget<NavigationRail>(find.byType(NavigationRail).last);
    expect(framed.selectedIndex, 1);

    // And from there, straight to another tab.
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('HISTORY'), findsNothing);
  });

  testWidgets('a desktop widens the rail to show the tab names',
      (tester) async {
    await _pumpAt(tester, 1400);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
  });

  test('centeredInsets centres content at its maximum width', () {
    // Narrower than the maximum: just the padding.
    expect(centeredInsets(500, maxWidth: 640), const EdgeInsets.all(16));
    // Wider: the rest splits evenly between the sides.
    final wide = centeredInsets(1032, maxWidth: 640);
    expect(wide.left, 16 + 180);
    expect(wide.right, 16 + 180);
    expect(wide.top, 16);
  });

  test('CardColumns fits as many columns as it can, up to the maximum', () {
    expect(CardColumns.columnsFor(400), 1);
    expect(CardColumns.columnsFor(732), 2);
    expect(CardColumns.columnsFor(1200), 3);
    expect(CardColumns.columnsFor(3000), 3);
  });

  testWidgets('SplitColumns stacks when narrow, in the narrow order',
      (tester) async {
    Future<void> pumpWidth(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SplitColumns(
            start: [Text('A')],
            end: [Text('B')],
            narrow: [Text('B'), Text('A')],
          ),
        ),
      ));
    }

    addTearDown(tester.view.reset);
    await pumpWidth(500);
    expect(tester.getTopLeft(find.text('B')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy));

    await pumpWidth(1000);
    expect(tester.getTopLeft(find.text('A')).dy,
        tester.getTopLeft(find.text('B')).dy);
    expect(tester.getTopLeft(find.text('A')).dx,
        lessThan(tester.getTopLeft(find.text('B')).dx));
  });

  testWidgets('SplitColumns runs "below" full width under both columns',
      (tester) async {
    Future<void> pumpWidth(double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SplitColumns(
            start: [Text('A')],
            end: [Text('B')],
            below: [SizedBox(height: 20, child: Text('CHART'))],
          ),
        ),
      ));
    }

    addTearDown(tester.view.reset);
    await pumpWidth(1000);
    final chart = tester.getRect(find.text('CHART'));
    expect(chart.top,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('A')).dy));
    expect(chart.left, tester.getTopLeft(find.text('A')).dx);

    // Stacked, it follows start and end once, unless narrow says otherwise.
    await pumpWidth(500);
    expect(find.text('CHART'), findsOneWidget);
    expect(tester.getTopLeft(find.text('CHART')).dy,
        greaterThan(tester.getTopLeft(find.text('B')).dy));
  });

  testWidgets('a button in an app bar lays out with the clinic theme',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildClinicTheme(null),
      home: Scaffold(
        appBar: AppBar(actions: [
          FilledButton(onPressed: () {}, child: const Text('Add patient')),
          OutlinedButton(onPressed: () {}, child: const Text('Today')),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Add patient')).width, lessThan(200));
  });
}
