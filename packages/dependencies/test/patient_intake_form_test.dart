import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:api_sdk/api_sdk.dart';

void main() {
  group('models', () {
    Map<String, dynamic> chart(Object? intake, {bool embed = true}) => {
          'id': 'c1',
          'person_id': 'p1',
          'clinic_id': 'dt',
          'person': {'full_name': 'Ana', 'sex': 'female', 'address': 'Pasig'},
          if (embed) 'intake': intake,
        };

    test('a chart knows whether its form is filled in, when asked', () {
      expect(Patient.fromJson(chart(null, embed: false)).hasIntake, isNull);
      expect(Patient.fromJson(chart(null)).hasIntake, isFalse);
      expect(Patient.fromJson(chart(const [])).hasIntake, isFalse);
      expect(Patient.fromJson(chart(const [{'updated_at': 'x'}])).hasIntake, isTrue);
      expect(Patient.fromJson(chart(const {'updated_at': 'x'})).hasIntake, isTrue);
    });

    test('the person\'s new details come through', () {
      final p = Patient.fromJson(chart(null));
      expect(p.sex, Sex.female);
      expect(p.address, 'Pasig');
    });

    test('an allergy this build does not know is skipped, not fatal', () {
      final i = PatientIntake.fromJson({
        'patient_id': 'c1',
        'under_treatment': false,
        'takes_medications': false,
        'allergies': ['latex', 'from_the_future'],
        'allergies_other': 'Shellfish',
        'conditions': ['asthma'],
        'consent_at': '2026-09-22T01:00:00Z',
        'signed_name': 'Ana',
        'source': 'front_desk_tablet',
        'updated_at': '2026-09-22T01:00:00Z',
      });
      expect(i.allergies, {IntakeAllergy.latex});
      expect(i.allergyLabels, ['Latex', 'Shellfish']);
      expect(i.hasAllergies, isTrue);
      expect(i.source, IntakeSource.frontDeskTablet);
    });
  });

  group('the form', () {
    late IntakeSubmission? sent;

    Future<void> pumpForm(WidgetTester tester, {bool isDental = true}) async {
      sent = null;
      tester.view.physicalSize = const Size(1280, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PatientIntakeForm(
            audience: IntakeAudience.patient,
            clinicName: 'D-Touch',
            isDental: isDental,
            submitLabel: 'Send',
            onSubmit: (form) async => sent = form,
          ),
        ),
      ));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Finder field(String label) =>
        find.widgetWithText(TextFormField, label);

    Future<void> next(WidgetTester tester) =>
        tap(tester, find.text('Next'));

    testWidgets('will not move on without the required answers', (tester) async {
      await pumpForm(tester);
      await next(tester);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Please choose one'), findsOneWidget);
    });

    testWidgets('a birthday must be a real date', (tester) async {
      await pumpForm(tester);
      await tester.enterText(field('Your birthday *'), '02311990');
      expect(find.text('02/31/1990'), findsOneWidget);
      await next(tester);
      expect(find.text('Use MM/DD/YYYY, e.g. 04/02/1990'), findsOneWidget);
    });

    testWidgets('filled in end to end, it sends what the database takes',
        (tester) async {
      await pumpForm(tester);

      await tester.enterText(field('Full name *'), '  Ana Cruz ');
      await tester.enterText(field('Your birthday *'), '04021990');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Female'));
      await next(tester);

      expect(find.text('Step 2 of 4'), findsOneWidget);
      await tester.enterText(field('Mobile number *'), '0917 555 0101');
      await tester.enterText(field('Contact name'), 'Ben Cruz');
      await next(tester);

      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(field('Last dental visit'), findsOneWidget);
      // Treatment: No. Medicines: Yes, then say which.
      await tap(tester, find.widgetWithText(OutlinedButton, 'No').first);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Yes').at(1));
      await next(tester);
      expect(find.text('Step 3 of 4'), findsOneWidget, reason: 'which medicines?');
      await tester.enterText(field('Which ones? *'), 'Losartan 50 mg');
      await tap(tester, find.widgetWithText(FilterChip, 'Penicillin'));
      // Asked of women only.
      expect(find.text('Are you pregnant?'), findsOneWidget);
      await next(tester);

      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('Penicillin'), findsOneWidget);
      // FilledButton.icon is a private subclass, so find it by its label.
      await tap(tester, find.text('Send'));
      expect(find.text('Please tick the box to continue'), findsOneWidget);
      await tap(tester, find.byType(Checkbox));
      await tester.enterText(field('Type your full name to sign *'), 'Ana Cruz');
      await tap(tester, find.text('Send'));

      // Confirm first.
      expect(find.text('Send your information?'), findsOneWidget);
      expect(sent, isNull);
      await tap(tester, find.widgetWithText(FilledButton, 'Send'));

      final form = sent!;
      expect(form.person['full_name'], 'Ana Cruz');
      expect(form.person['date_of_birth'], '1990-04-02');
      expect(form.person['sex'], 'female');
      expect(form.person['phone'], '0917 555 0101');
      expect(form.person['email'], isNull);
      expect(form.person['emergency_contact_name'], 'Ben Cruz');
      expect(form.intake['under_treatment'], isFalse);
      expect(form.intake['takes_medications'], isTrue);
      expect(form.intake['medications'], 'Losartan 50 mg');
      expect(form.intake['allergies'], ['penicillin']);
      expect(form.intake['conditions'], isEmpty);
      expect(form.intake['pregnant'], isNull);
      expect(form.intake['signed_name'], 'Ana Cruz');
      expect(form.intake['consent'], isTrue);
    });

    testWidgets('a parent answers for their child, and signs', (tester) async {
      await pumpForm(tester);
      expect(field('Your full name *'), findsNothing, reason: 'optional, off');
      await tap(tester, find.byType(Switch));
      expect(find.text('About you and the patient'), findsOneWidget);

      await next(tester);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Please choose one'), findsNWidgets(2));

      await tester.enterText(field('Your full name *'), ' Rosa Santos ');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Parent'));
      await tester.enterText(field('Your mobile number *'), '0917 555 0133');
      await tester.enterText(field("Patient's full name *"), 'Lia Santos');
      // Asked about the patient now, not "you".
      expect(field('Your birthday *'), findsNothing);
      await tester.enterText(field('Birthday *'), '05062018');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Female'));
      await next(tester);

      await tester.enterText(field('Mobile number *'), '0917 555 0133');
      await next(tester);

      expect(find.text('Are you pregnant?'), findsNothing);
      // Treatment, then medicines: each answered No drops out of the finder.
      await tap(tester, find.widgetWithText(OutlinedButton, 'No').first);
      await tap(tester, find.widgetWithText(OutlinedButton, 'No').first);
      await next(tester);

      expect(find.text('Rosa Santos (Parent) · 0917 555 0133'), findsOneWidget);
      expect(find.textContaining('As the patient\'s parent or guardian'),
          findsOneWidget);
      await tap(tester, find.byType(Checkbox));
      await tester.enterText(field('Type your full name to sign *'), 'Rosa Santos');
      await tap(tester, find.text('Send'));
      expect(find.text('Send this information?'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Send'));

      final form = sent!;
      expect(form.person['full_name'], 'Lia Santos');
      expect(form.intake['filled_by_guardian'], isTrue);
      expect(form.intake['guardian_name'], 'Rosa Santos');
      expect(form.intake['guardian_relationship'], 'parent');
      expect(form.intake['guardian_phone'], '0917 555 0133');
      expect(form.intake['guardian_email'], isNull);
      expect(form.intake['signed_name'], 'Rosa Santos');
    });

    testWidgets('switched back off, no guardian is sent', (tester) async {
      await pumpForm(tester);
      await tap(tester, find.byType(Switch));
      await tester.enterText(field('Your full name *'), 'Rosa');
      await tap(tester, find.byType(Switch));
      expect(field('Your full name *'), findsNothing);
      expect(field('Your birthday *'), findsOneWidget);
    });

    test('a guardian comes back from the row, or none', () {
      Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
            'patient_id': 'c1',
            'under_treatment': false,
            'takes_medications': false,
            'consent_at': '2026-09-22T01:00:00Z',
            'signed_name': 'Rosa',
            'source': 'patient_app',
            'updated_at': '2026-09-22T01:00:00Z',
            ...extra,
          };
      expect(PatientIntake.fromJson(row()).guardian, isNull);
      final g = PatientIntake.fromJson(row({
        'guardian_name': 'Rosa',
        'guardian_relationship': 'parent',
        'guardian_phone': '0917',
      })).guardian!;
      expect(g.relationship, GuardianRelationship.parent);
      expect(g.email, isNull);
    });

    testWidgets('no dental questions outside a dental clinic', (tester) async {
      await pumpForm(tester, isDental: false);
      await tester.enterText(field('Full name *'), 'Ana');
      await tester.enterText(field('Your birthday *'), '04021990');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Male'));
      await next(tester);
      await tester.enterText(field('Mobile number *'), '0917 555 0101');
      await next(tester);
      expect(field('Last dental visit'), findsNothing);
      expect(find.text('Are you pregnant?'), findsNothing);
    });
  });
}
