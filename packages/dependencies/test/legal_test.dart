import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

import 'clinic_router_test.dart' show dtouch, pumpApp;

/// Remembers the sign-ups it was asked for: the versions agreed to.
class SignUpRepository extends HealthRepository {
  // Built inside a widget test, so no token refresh timer left running.
  SignUpRepository()
      : super(SupabaseClient('http://localhost', 'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final signUps = <(String?, String?)>[];

  @override
  Future<void> signUp(
    String email,
    String password,
    String fullName, {
    String? captchaToken,
    String? privacyPolicyVersion,
    String? termsVersion,
  }) async =>
      signUps.add((privacyPolicyVersion, termsVersion));
}

Future<SignUpRepository> pumpSignUp(WidgetTester tester) async {
  final repo = SignUpRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appRoleProvider.overrideWithValue(AppRole.patient),
      preferencesProvider.overrideWithValue(AppPreferences.memory()),
      routeBrandClinicProvider.overrideWithValue(dtouch),
      healthRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(
      home: SignInScreen(appName: 'Patient', initialSignUp: true),
    ),
  ));
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'), 'Juan dela Cruz');
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'), 'juan@email.com');
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'), 'secret123');
  return repo;
}

const _mustTick = 'Tick the box to agree to the Terms and Conditions';

String _text(LegalDocument d) => [
      d.intro,
      for (final s in d.sections) ...[s.heading, ...s.body],
    ].join(' ');

void main() {
  group('create account', () {
    testWidgets('the box starts unticked, and blocks the form',
        (tester) async {
      final repo = await pumpSignUp(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text(_mustTick), findsOneWidget);
      expect(repo.signUps, isEmpty);
    });

    testWidgets('once ticked, the account records both versions',
        (tester) async {
      final repo = await pumpSignUp(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pump();

      expect(repo.signUps,
          [(PrivacyPolicy.version, TermsAndConditions.version)]);
      expect(find.text(_mustTick), findsNothing);
    });

    for (final d in [PrivacyPolicy.document, TermsAndConditions.document]) {
      testWidgets('the ${d.title} is a tap away', (tester) async {
        await pumpSignUp(tester);
        await tester.tap(find.text(d.title));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(AppBar, d.title), findsOneWidget);
        expect(find.textContaining('1. ${d.sections.first.heading}'),
            findsOneWidget);
        await tester.scrollUntilVisible(
            find.textContaining('Questions? Email'), 400);
      });
    }

    testWidgets('signing in shows no box', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appRoleProvider.overrideWithValue(AppRole.patient),
          preferencesProvider.overrideWithValue(AppPreferences.memory()),
          routeBrandClinicProvider.overrideWithValue(dtouch),
        ],
        child: const MaterialApp(home: SignInScreen(appName: 'Patient')),
      ));
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('the documents', () {
    test('are dated, as the database takes it', () {
      for (final d in [PrivacyPolicy.document, TermsAndConditions.document]) {
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d.version), isTrue);
        expect(d.dated, 'September 30, 2026');
      }
      // The ids the database's `document` column accepts.
      expect(PrivacyPolicy.document.id, 'privacy');
      expect(TermsAndConditions.document.id, 'terms');
    });

    test('name the operator and where to write', () {
      for (final d in [PrivacyPolicy.document, TermsAndConditions.document]) {
        expect(_text(d), contains('D-Touch Dental Clinic'));
        expect(_text(d), contains('dtouchdental@gmail.com'));
      }
    });

    test('the Privacy Policy says what the law asks it to', () {
      final headings = [
        for (final s in PrivacyPolicy.document.sections) s.heading,
      ];
      expect(
          headings,
          containsAll([
            'Who we are',
            'What we collect',
            'How long we keep it',
            'Your rights',
          ]));
      final text = _text(PrivacyPolicy.document);
      expect(text, contains('Republic Act No. 10173'));
      // Data leaves the country: that must be said.
      expect(text, contains('Mumbai, India'));
      expect(text, contains('72 hours'));
      expect(text, contains('privacy.gov.ph'));
    });

    test('the Terms say the apps are not for emergencies', () {
      expect(_text(TermsAndConditions.document), contains('911'));
    });

    testWidgets('are at /privacy and /terms for anyone', (tester) async {
      final h = await pumpApp(tester, app: AppRole.patient);
      expect(await h.go('/privacy'), '/privacy');
      expect(find.widgetWithText(AppBar, 'Privacy Policy'), findsOneWidget);
      expect(await h.go('/terms'), '/terms');
      expect(
          find.widgetWithText(AppBar, 'Terms and Conditions'), findsOneWidget);

      await h.signIn();
      expect(await h.go('/privacy'), '/privacy');
      expect(await h.go('/terms'), '/terms');
    });
  });
}
