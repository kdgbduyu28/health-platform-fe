import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:api_sdk/api_sdk.dart';

var _seq = 0;

/// An entry recorded [minutes] after the first, so order is explicit.
DentalEntry entry(
  int tooth,
  DentalCode code, {
  DentalEntryStatus status = DentalEntryStatus.existing,
  Set<ToothSurface> surfaces = const {},
  String? visit,
  int minutes = 0,
}) =>
    DentalEntry(
      id: 'e${_seq++}',
      tooth: tooth,
      code: code,
      status: status,
      surfaces: surfaces,
      appointmentId: visit,
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: minutes)),
    );

const o = ToothSurface.occlusal, d = ToothSurface.distal, m = ToothSurface.mesial;

void main() {
  group('numbering', () {
    test('FDI to Universal, permanent teeth', () {
      expect(universalLabel(18), '1');
      expect(universalLabel(11), '8');
      expect(universalLabel(21), '9');
      expect(universalLabel(28), '16');
      expect(universalLabel(38), '17');
      expect(universalLabel(31), '24');
      expect(universalLabel(41), '25');
      expect(universalLabel(48), '32');
    });

    test('FDI to Universal, primary teeth', () {
      expect(universalLabel(55), 'A');
      expect(universalLabel(51), 'E');
      expect(universalLabel(61), 'F');
      expect(universalLabel(65), 'J');
      expect(universalLabel(75), 'K');
      expect(universalLabel(71), 'O');
      expect(universalLabel(81), 'P');
      expect(universalLabel(85), 'T');
    });

    test('every tooth on the chart has a distinct Universal label', () {
      for (final dentition in Dentition.values) {
        final teeth = [...dentition.upper, ...dentition.lower];
        expect(teeth.map(universalLabel).toSet(), hasLength(teeth.length));
      }
    });

    test('teeth are named the way a dentist says them', () {
      expect(toothName(46), 'Lower right first molar');
      expect(toothName(21), 'Upper left central incisor');
      expect(toothName(38), 'Lower left third molar');
      expect(toothName(55), 'Upper right baby second molar');
    });

    test('front teeth have incisal and facial surfaces; upper ones palatal',
        () {
      expect(ToothSurface.occlusal.labelFor(11), 'Incisal');
      expect(ToothSurface.buccal.labelFor(43), 'Facial');
      expect(ToothSurface.occlusal.labelFor(36), 'Occlusal');
      expect(ToothSurface.lingual.labelFor(16), 'Palatal');
      expect(ToothSurface.lingual.labelFor(46), 'Lingual');
    });

    test('children are charted on baby teeth by default', () {
      expect(Dentition.forAge(6), Dentition.primary);
      expect(Dentition.forAge(30), Dentition.permanent);
      expect(Dentition.forAge(null), Dentition.permanent);
    });
  });

  group('the chart', () {
    test('a filling replaces the decay on the surfaces it repairs', () {
      final chart = DentalChart([
        entry(46, DentalCode.caries, surfaces: {o, d}),
        entry(46, DentalCode.filling,
            status: DentalEntryStatus.done, surfaces: {o}, visit: 'v2',
            minutes: 5),
      ]);
      final t = chart.stateOf(46);
      expect(t.surfaces[o], DentalCode.filling);
      expect(t.surfaces[d], DentalCode.caries);
      expect(t.hasProblem, isTrue);
    });

    test('order is by when it was recorded, not the order rows arrive', () {
      final chart = DentalChart([
        entry(46, DentalCode.filling,
            status: DentalEntryStatus.done, surfaces: {o}, minutes: 5),
        entry(46, DentalCode.caries, surfaces: {o}),
      ]);
      expect(chart.stateOf(46).surfaces[o], DentalCode.filling);
    });

    test('planned work changes nothing until it is done', () {
      final chart = DentalChart([
        entry(46, DentalCode.caries, surfaces: {o}),
        entry(46, DentalCode.rootCanal, status: DentalEntryStatus.planned),
      ]);
      final t = chart.stateOf(46);
      expect(t.whole, isEmpty);
      expect(t.planned.single.code, DentalCode.rootCanal);
      expect(chart.plan.single.tooth, 46);
    });

    test('an extraction clears the tooth; a later implant brings it back', () {
      final extracted = DentalChart([
        entry(36, DentalCode.filling, surfaces: {m, o}),
        entry(36, DentalCode.extraction,
            status: DentalEntryStatus.done, visit: 'v1', minutes: 1),
      ]);
      expect(extracted.stateOf(36).missing, isTrue);
      expect(extracted.stateOf(36).surfaces, isEmpty);
      expect(extracted.stateOf(36).headline, DentalCode.missing);

      final implanted = DentalChart([
        ...extracted.entries,
        entry(36, DentalCode.implant,
            status: DentalEntryStatus.done, visit: 'v2', minutes: 2),
      ]);
      expect(implanted.stateOf(36).missing, isFalse);
      expect(implanted.stateOf(36).headline, DentalCode.implant);
    });

    test('a crown covers every surface', () {
      final chart = DentalChart([
        entry(16, DentalCode.caries, surfaces: {o, d}),
        entry(16, DentalCode.crown,
            status: DentalEntryStatus.done, visit: 'v1', minutes: 1),
      ]);
      final t = chart.stateOf(16);
      expect(t.surfaces, isEmpty);
      expect(t.headline, DentalCode.crown);
      expect(t.hasProblem, isFalse);
    });

    test('a root canal is what the tooth shows even under a filling', () {
      final chart = DentalChart([
        entry(46, DentalCode.rootCanal, status: DentalEntryStatus.done,
            visit: 'v1'),
        entry(46, DentalCode.filling,
            status: DentalEntryStatus.done, surfaces: {o}, visit: 'v1',
            minutes: 1),
      ]);
      expect(chart.stateOf(46).headline, DentalCode.rootCanal);
      expect(chart.stateOf(46).surfaces[o], DentalCode.filling);
    });

    test('lists what was recorded at one visit, in tooth order', () {
      final chart = DentalChart([
        entry(46, DentalCode.caries, surfaces: {o}, visit: 'v1'),
        entry(16, DentalCode.sealant,
            status: DentalEntryStatus.done, surfaces: {o}, visit: 'v1'),
        entry(21, DentalCode.crown, status: DentalEntryStatus.planned),
      ]);
      expect([for (final e in chart.atVisit('v1')) e.tooth], [16, 46]);
      expect(chart.atVisit('v2'), isEmpty);
    });

    test('knows which dentition has been charted', () {
      expect(DentalChart([entry(85, DentalCode.sealant)]).hasPrimaryTeeth,
          isTrue);
      expect(DentalChart([entry(85, DentalCode.sealant)]).hasPermanentTeeth,
          isFalse);
    });

    test('an untouched tooth is empty and healthy', () {
      final t = DentalChart(const []).stateOf(11);
      expect(t.isEmpty, isTrue);
      expect(describeTooth(t), 'Nothing recorded');
    });
  });

  group('entries', () {
    test('read from the table, surfaces in any order', () {
      final e = DentalEntry.fromJson({
        'id': 'x',
        'tooth': 46,
        'code': 'filling',
        'status': 'done',
        'surfaces': ['O', 'D', 'M'],
        'appointment_id': 'a1',
        'note': 'Composite',
        'created_at': '2026-09-01T02:00:00Z',
      });
      expect(e.code, DentalCode.filling);
      expect(e.status, DentalEntryStatus.done);
      expect(e.describe(ToothNumbering.fdi), 'Filling 46 · MOD');
      expect(e.describe(ToothNumbering.universal), 'Filling 30 · MOD');
      expect(e.note, 'Composite');
    });

    test('read from the patient function, which has no note', () {
      final e = DentalEntry.fromJson({
        'id': 'x',
        'tooth': 46,
        'code': 'root_canal',
        'status': 'planned',
        'surfaces': <String>[],
        'appointment_id': null,
      });
      expect(e.note, isNull);
      expect(e.describe(ToothNumbering.fdi, forPatient: true),
          'Root canal treatment 46');
    });

    test('a condition can only be found; an extraction never "found"', () {
      expect(DentalCode.caries.allowedStatuses, [DentalEntryStatus.existing]);
      expect(DentalCode.extraction.allowedStatuses,
          isNot(contains(DentalEntryStatus.existing)));
      expect(DentalCode.crown.allowedStatuses, DentalEntryStatus.values);
    });
  });

  group('clinic type', () {
    test('a dental vertical charts teeth; others do not', () {
      Clinic of(String? kind) => Clinic.fromJson({
            'id': 'c',
            'name': 'C',
            'slug': 'c',
            'type': 'dental',
            'clinic_type': {
              'display_name': 'Dental',
              'icon_name': 'medical_services',
              'chart_kind': kind,
            },
          });
      expect(of('dental').isDental, isTrue);
      expect(of(null).isDental, isFalse);
    });
  });

  group('preferences', () {
    test('tooth numbering is remembered, FDI until chosen', () {
      final prefs = AppPreferences.memory();
      final container = ProviderContainer(
          overrides: [preferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      expect(container.read(toothNumberingProvider), ToothNumbering.fdi);
      container
          .read(toothNumberingProvider.notifier)
          .set(ToothNumbering.universal);
      expect(prefs.toothNumbering, ToothNumbering.universal);
      expect(container.read(toothNumberingProvider), ToothNumbering.universal);
    });

    test('the last clinic is remembered per app', () async {
      final prefs = AppPreferences.memory();
      await prefs.setLastClinicSlug(AppRole.doctor, 'dtouchdental');
      expect(prefs.lastClinicSlug(AppRole.doctor), 'dtouchdental');
      expect(prefs.lastClinicSlug(AppRole.patient), isNull);
    });
  });

  group('odontogram', () {
    testWidgets('draws both arches and reports taps by FDI number',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: Odontogram(
              chart: DentalChart([entry(46, DentalCode.caries, surfaces: {o})]),
              dentition: Dentition.permanent,
              numbering: ToothNumbering.fdi,
              onToothTap: (t) => tapped = t,
            ),
          ),
        ),
      ));
      for (final t in ['18', '11', '21', '28', '48', '41', '31', '38']) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.text('46'));
      expect(tapped, 46);
      expect(
          find.bySemanticsLabel(RegExp(r'^Tooth 46, Lower right first molar')),
          findsOneWidget);
    });

    testWidgets('scrolls rather than squashes on a narrow screen',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Odontogram(
              chart: DentalChart(const []),
              dentition: Dentition.permanent,
              numbering: ToothNumbering.universal,
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });
  });
}
