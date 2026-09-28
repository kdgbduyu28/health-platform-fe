import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:api_sdk/api_sdk.dart';

// openInClinic against the shape every staff app has: the clinic's shell, a
// tab bar, and a visit page and a history page outside it that link to each
// other.

Widget _page(BuildContext context, String title, Map<String, String> links) =>
    Scaffold(
      body: Column(children: [
        Text(title),
        for (final e in links.entries)
          TextButton(
            onPressed: () => context.openInClinic(e.value),
            child: Text(e.key),
          ),
      ]),
    );

GoRouter _router() => GoRouter(
      initialLocation: '/dt/dashboard',
      routes: [
        ShellRoute(
          builder: (_, __, child) => child,
          routes: [
            GoRoute(
              path: '/:clinic',
              // Builds no page, as in createClinicRouter.
              redirect: (_, __) => null,
              routes: [
                GoRoute(
                  path: 'appointments/:id',
                  builder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return _page(context, 'VISIT $id', {
                      'history': '/patients/p1',
                      'older visit': '/appointments/${id}0',
                    });
                  },
                ),
                GoRoute(
                  path: 'patients/:id',
                  builder: (context, _) => _page(context, 'HISTORY', {
                    'visit 1': '/appointments/1',
                    'visit 2': '/appointments/2',
                  }),
                ),
                StatefulShellRoute.indexedStack(
                  builder: (_, __, shell) => shell,
                  branches: [
                    StatefulShellBranch(routes: [
                      GoRoute(
                        path: 'dashboard',
                        builder: (context, _) => _page(
                            context, 'DASHBOARD', {'visit 1': '/appointments/1'}),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  late GoRouter router;

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    router.pop();
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    router = _router();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('visit → history → the same visit goes back, not deeper',
      (tester) async {
    await pumpApp(tester);
    await tap(tester, 'visit 1');
    await tap(tester, 'history');
    await tap(tester, 'visit 1');
    expect(find.text('VISIT 1'), findsOneWidget);
    await tap(tester, 'history');
    expect(find.text('HISTORY'), findsOneWidget);

    // However often they went round, Back is two steps from home.
    await back(tester);
    expect(find.text('VISIT 1'), findsOneWidget);
    await back(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(router.canPop(), isFalse);
  });

  testWidgets('a page not yet open is pushed on top', (tester) async {
    await pumpApp(tester);
    await tap(tester, 'visit 1');
    await tap(tester, 'history');
    await tap(tester, 'visit 2');
    expect(find.text('VISIT 2'), findsOneWidget);

    await back(tester);
    expect(find.text('HISTORY'), findsOneWidget);
    await back(tester);
    expect(find.text('VISIT 1'), findsOneWidget);
  });

  testWidgets('history reached through several visits returns to the one open',
      (tester) async {
    await pumpApp(tester);
    await tap(tester, 'visit 1');
    await tap(tester, 'older visit'); // VISIT 10
    await tap(tester, 'history');
    await tap(tester, 'visit 1');
    // Back to the first visit: VISIT 10 and HISTORY above it are gone.
    expect(find.text('VISIT 1'), findsOneWidget);
    await back(tester);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });
}
