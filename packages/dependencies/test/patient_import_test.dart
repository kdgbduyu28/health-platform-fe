import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

Map<String, dynamic> _row(List<String> headers, List<String> cells,
        {DateOrder order = DateOrder.monthFirst}) =>
    readPatientRow(cells, matchHeaders(headers), row: 2, dateOrder: order).json;

void main() {
  group('CSV', () {
    test('reads quotes, commas, line breaks and doubled quotes', () {
      final rows = parseCsv('﻿Name,Notes\r\n'
          '"Cruz, Ana","Said ""hi""\nthen left"\r\n'
          'Ben,\r\n'
          ',,\r\n');
      expect(rows, [
        ['Name', 'Notes'],
        ['Cruz, Ana', 'Said "hi"\nthen left'],
        ['Ben', ''],
      ]);
    });

    test('reads a semicolon file from a comma-decimal Excel', () {
      expect(parseCsv('Name;Balance\nAna;1,50\n'), [
        ['Name', 'Balance'],
        ['Ana', '1,50'],
      ]);
    });

    test('writes what it reads back, BOM first', () {
      final rows = [
        ['Name', 'Notes', 'Phone'],
        ['Peña, Ana', 'Line one\nline "two"', '+63 917 555 0101'],
      ];
      final text = toCsv(rows);
      expect(text.startsWith('﻿'), isTrue);
      expect(parseCsv(text), rows);
    });

    test('a formula is written as text and read back as typed', () {
      final text = toCsv([
        ['=HYPERLINK("x")', '-150', '@SUM(A1)'],
      ]);
      expect(text, contains("'=HYPERLINK"));
      expect(text, contains(',-150,'));
      final cells = parseCsv(text).single;
      expect(unescapeCell(cells[0]), '=HYPERLINK("x")');
      expect(unescapeCell(cells[1]), '-150');
    });

    test('a Windows Excel file (not UTF-8) keeps its ñ', () {
      final bytes = Uint8List.fromList(latin1.encode('Name\nPeña'));
      expect(decodeTextFile(bytes), 'Name\nPeña');
      expect(decodeTextFile(Uint8List.fromList(utf8.encode('Peña'))), 'Peña');
    });
  });

  group('columns', () {
    test('headers clinics use are recognised, each column once', () {
      expect(
        matchHeaders(['Surname', 'First Name', 'Mobile No.', 'Birthdate',
            'Gender', 'Remarks', 'Mobile', 'Favourite colour']),
        [
          PatientColumn.lastName,
          PatientColumn.firstName,
          PatientColumn.phone,
          PatientColumn.dateOfBirth,
          PatientColumn.sex,
          PatientColumn.chartNote,
          null, // phone is taken
          null,
        ],
      );
    });

    test('an export\'s headers come back as the same columns', () {
      final cols = PatientColumn.exported(withNotes: true);
      final matched = matchHeaders([for (final c in cols) c.header]);
      for (var i = 0; i < cols.length; i++) {
        expect(matched[i], cols[i].exportOnly ? null : cols[i], reason: cols[i].header);
      }
    });

    test('the front desk\'s export has no notes column', () {
      expect(PatientColumn.exported(withNotes: false), isNot(contains(PatientColumn.chartNote)));
      expect(PatientColumn.template, isNot(contains(PatientColumn.patientId)));
    });
  });

  group('values', () {
    test('dates, either way round', () {
      expect(parseDate('1990-04-03', DateOrder.dayFirst), DateTime(1990, 4, 3));
      expect(parseDate('03/04/1990', DateOrder.monthFirst), DateTime(1990, 3, 4));
      expect(parseDate('03/04/1990', DateOrder.dayFirst), DateTime(1990, 4, 3));
      expect(parseDate('3/4/90', DateOrder.monthFirst), DateTime(1990, 3, 4));
      expect(parseDate('March 4, 1990', DateOrder.dayFirst), DateTime(1990, 3, 4));
      expect(parseDate('4 Mar 1990', DateOrder.monthFirst), DateTime(1990, 3, 4));
      expect(parseDate('04/31/1990', DateOrder.monthFirst), isNull);
      expect(parseDate('soon', DateOrder.monthFirst), isNull);
    });

    test('names as clinics type them', () {
      expect(tidyName('DELA CRUZ, JUAN'), 'Juan Dela Cruz');
      expect(tidyName('Juan dela Cruz, Jr.'), 'Juan dela Cruz, Jr.');
      expect(tidyName('  ana   peña '), 'ana peña');
      expect(tidyName('MA. ÑORA'), 'Ma. Ñora');
    });

    test('yes and no, in English and Filipino', () {
      expect(parseYesNo('Oo'), isTrue);
      expect(parseYesNo('hindi'), isFalse);
      expect(parseYesNo('maybe'), isNull);
      expect(parsePesos('₱1,500.50'), 1500.5);
      expect(parsePesos('PHP 200'), 200);
    });
  });

  group('a row', () {
    test('becomes the person, the form, the note and the balance', () {
      final json = _row([
        'Chart No.', 'Last name', 'First name', 'Mobile', 'Birthday', 'Sex',
        'Medications', 'Allergies', 'Medical history', 'Under treatment',
        'Signed by', 'Notes', 'Balance forwarded',
      ], [
        'A-1', 'REYES', 'MARIA', '0917 555 0101', '07/22/1985', 'F',
        'Losartan', 'Penicillin; lidocaine; shrimp', 'Hypertension, TB', 'no',
        'Maria Reyes', 'Gag reflex', '₱1,500.50',
      ]);
      expect(json['chart_number'], 'A-1');
      expect(json['person'], {
        'full_name': 'Maria Reyes',
        'phone': '0917 555 0101',
        'date_of_birth': '1985-07-22',
        'sex': 'female',
      });
      final intake = json['intake'] as Map<String, dynamic>;
      expect(intake['takes_medications'], isTrue, reason: 'a medicine is named');
      expect(intake['under_treatment'], isFalse);
      expect(intake['allergies'], ['penicillin', 'local_anesthetic']);
      expect(intake['allergies_other'], 'shrimp');
      expect(intake['conditions'], ['high_blood_pressure', 'tuberculosis']);
      expect(intake['signed_name'], 'Maria Reyes');
      expect(json['chart_note'], 'Gag reflex');
      expect(json['opening_balance'], '1500.50');
    });

    test('says what is wrong with it', () {
      final r = readPatientRow(['', 'X', '13/13/2000', 'Rosa'],
          matchHeaders(['Name', 'Sex', 'Birthday', 'Guardian']), row: 7);
      expect(r.ok, isFalse);
      expect(r.errors, containsAll([
        'Sex "X" is not Female or Male.',
        'Birthday "13/13/2000" is not a date.',
        'No name.',
        'A guardian needs a relationship (Parent or Guardian) and a phone.',
      ]));
    });

    test('with no form columns filled, sends no form', () {
      final json = _row(['Name', 'Allergies'], ['Ana Cruz', 'none']);
      expect(json.containsKey('intake'), isFalse);
      expect(json['person'], {'full_name': 'Ana Cruz'});
    });

    test('an exported patient imports back as the same', () {
      final exported = {
        'patient_id': '30000000-0000-0000-0000-000000000002',
        'chart_number': 'M-7',
        'full_name': 'Maria Reyes',
        'phone': '+63 928 123 4567',
        'date_of_birth': '1985-07-22',
        'sex': 'female',
        'intake': {
          'under_treatment': false,
          'takes_medications': true,
          'medications': 'Losartan',
          'allergies': ['latex'],
          'conditions': ['diabetes'],
          'guardian_name': 'Rosa Reyes',
          'guardian_relationship': 'parent',
          'guardian_phone': '0917',
          'signed_name': 'Rosa Reyes',
          'signed_on': '2024-05-06',
        },
        'chart_note': 'Gag reflex',
        'balance': 250,
        'completed_visits': 3,
      };
      final cols = PatientColumn.exported(withNotes: true);
      final text = toCsv([
        [for (final c in cols) c.header],
        exportPatientCells(exported, cols),
      ]);
      final rows = parseCsv(text);
      final back = readPatientRow(rows[1], matchHeaders(rows[0]), row: 2);
      expect(back.ok, isTrue, reason: back.errors.join());
      expect(back.json['patient_id'], exported['patient_id']);
      expect(back.json['chart_number'], 'M-7');
      expect(back.json['person'], {
        'full_name': 'Maria Reyes',
        'phone': '+63 928 123 4567',
        'date_of_birth': '1985-07-22',
        'sex': 'female',
      });
      expect(back.json['intake'], {
        'under_treatment': false,
        'takes_medications': true,
        'medications': 'Losartan',
        'allergies': ['latex'],
        'conditions': ['diabetes'],
        'guardian_name': 'Rosa Reyes',
        'guardian_relationship': 'parent',
        'guardian_phone': '0917',
        'signed_name': 'Rosa Reyes',
        'signed_on': '2024-05-06',
      });
      expect(back.json['chart_note'], 'Gag reflex');
      expect(back.json.containsKey('opening_balance'), isFalse,
          reason: 'what they owe now is not an old balance to add');
    });
  });


  group('visits', () {
    test('times as clinics write them', () {
      expect(parseTime('9:00'), '09:00');
      expect(parseTime('9.30'), '09:30');
      expect(parseTime('2 PM'), '14:00');
      expect(parseTime('2:30pm'), '14:30');
      expect(parseTime('12 am'), '00:00');
      expect(parseTime('14:30'), '14:30');
      expect(parseTime('9'), isNull);
      expect(parseTime('25:00'), isNull);
    });

    test('a doctor in a file is found on the roster', () {
      const roster = {'Maria Santos': 'd1', 'Jose Reyes': 'd2', 'Ana Santos': 'd3'};
      expect(matchDoctor('Dra. Maria Santos', roster), 'd1');
      expect(matchDoctor('REYES', roster), 'd2');
      expect(matchDoctor('Santos', roster), isNull, reason: 'two Santoses');
      expect(matchDoctor('Dr. Lim', roster), isNull);
    });

    test('a row becomes the visit', () {
      final headers = ['Chart No.', 'Patient Name', 'Date of Visit', 'Time',
          'Dentist', 'Procedure', 'Remarks', 'Status'];
      final r = readVisitRow(
        ['A-1', 'REYES, MARIA', '01/10/2023', '2:30 PM', 'Dra. Santos',
            'Oral prophylaxis', 'Bleeding gums', 'done'],
        VisitColumn.match(headers),
        row: 2,
        doctors: const {'Dra. Santos': 'd1'},
      );
      expect(r.ok, isTrue, reason: r.errors.join());
      expect(r.json, {
        'row': 2,
        'chart_number': 'A-1',
        'patient_name': 'Maria Reyes',
        'date': '2023-01-10',
        'time': '14:30',
        'doctor_id': 'd1',
        'service': 'Oral prophylaxis',
        'visit_note': 'Bleeding gums',
        'status': 'completed',
      });
    });

    test('says what is wrong with a row', () {
      final r = readVisitRow(['', '31/31/2023', 'Dr. Who', 'soon', 'later'],
          VisitColumn.match(['Patient', 'Date', 'Doctor', 'Time', 'Status']),
          row: 3, doctors: const {});
      expect(r.errors, [
        'No patient: give a chart number or a name.',
        'Date "31/31/2023" is not a date.',
        'Time "soon" is not a time.',
        'Doctor "Dr. Who" is not matched to anyone on the roster.',
        'Status "later" is not Completed, Cancelled, No-show, Pending or Confirmed.',
      ]);
    });

    test('an export imports back', () {
      final cols = VisitColumn.exported(withNotes: true);
      final text = toCsv([
        [for (final c in cols) c.header],
        exportVisitCells({
          'patient_id': '30000000-0000-0000-0000-000000000001',
          'chart_number': null,
          'patient_name': 'Juan dela Cruz',
          'date': '2023-01-10',
          'time': '09:00',
          'doctor': 'Maria Santos',
          'service': 'Teeth Cleaning',
          'duration_minutes': 45,
          'status': 'no_show',
          'visit_note': null,
          'patient_note': null,
        }, cols),
      ]);
      final rows = parseCsv(text);
      final back = readVisitRow(rows[1], VisitColumn.match(rows[0]),
          row: 2, doctors: const {'Maria Santos': 'd1'});
      expect(back.ok, isTrue, reason: back.errors.join());
      expect(back.json['status'], 'no_show');
      expect(back.json['patient_id'], '30000000-0000-0000-0000-000000000001');
      expect(back.json['time'], '09:00');
      expect(back.json['duration_minutes'], 45);
    });
  });

  group('dental chart', () {
    test('teeth in either numbering, as FDI', () {
      expect(parseTooth('16', ToothNumbering.fdi), 16);
      expect(parseTooth('#3', ToothNumbering.universal), 16);
      expect(parseTooth('30', ToothNumbering.universal), 46);
      expect(parseTooth('A', ToothNumbering.fdi), 55);
      expect(parseTooth('19', ToothNumbering.fdi), isNull);
      expect(parseTooth('33', ToothNumbering.universal), isNull);
    });

    test('surfaces, codes and statuses as dentists write them', () {
      expect(parseSurfaces('MOD'), ['D', 'M', 'O']);
      expect(parseSurfaces('incisal, facial'), ['B', 'O']);
      expect(parseSurfaces('MX'), isNull);
      expect(parseDentalCode('RCT'), DentalCode.rootCanal);
      expect(parseDentalCode('Pasta'), DentalCode.filling);
      expect(parseDentalCode('Decay'), DentalCode.caries);
      expect(parseDentalCode('Jacket crown'), DentalCode.crown);
      expect(parseDentalCode('braces'), isNull);
      expect(parseDentalStatus('On exam'), DentalEntryStatus.existing);
      expect(parseDentalStatus('to do'), DentalEntryStatus.planned);
    });

    test('a row becomes a chart entry; an export comes back the same', () {
      final cols = DentalColumn.exported;
      final text = toCsv([
        [for (final c in cols) c.header],
        exportDentalCells({
          'patient_id': null,
          'chart_number': 'A-1',
          'patient_name': 'Maria Reyes',
          'tooth': 16,
          'surfaces': 'MO',
          'code': 'root_canal',
          'status': 'done',
          'date': '2023-01-10',
          'note': 'Two canals',
        }, cols),
      ]);
      final rows = parseCsv(text);
      expect(rows[1].sublist(4, 7), ['MO', 'Root canal', 'Done']);
      final back = readDentalRow(rows[1], DentalColumn.match(rows[0]), row: 2);
      expect(back.ok, isTrue, reason: back.errors.join());
      expect(back.json, {
        'row': 2,
        'chart_number': 'A-1',
        'patient_name': 'Maria Reyes',
        'tooth': 16,
        'code': 'root_canal',
        'surfaces': ['M', 'O'],
        'status': 'done',
        'date': '2023-01-10',
        'note': 'Two canals',
      });
    });
  });

  group('import screen', () {
    // Made outside the test: the Supabase client starts a timer.
    late final _ImportRepo repo;
    setUpAll(() => repo = _ImportRepo());

    testWidgets('columns, check, decide a duplicate, import', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appRoleProvider.overrideWithValue(AppRole.assistant),
          currentUserIdProvider.overrideWithValue('u1'),
          currentClinicProvider.overrideWithValue(const AsyncValue.data(_clinic)),
          canSeeClinicalNotesProvider.overrideWith((ref) async => false),
          healthRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: ImportFlow(spec: ImportSpec.of(ImportKind.patients), fileName: 'old.csv', rows: parseCsv(
            'Patient name,Mobile,Remarks,Shoe size\n'
            'Ana Cruz,0917 555 0101,Nervous,7\n'
            'Maria Reyes,0928 123 4567,,8\n'
            ',0917,,9\n'
            'Ana Cruz,0917-555-0101,,7\n',
          )),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Shoe size'), findsOneWidget);
      expect(find.text("Don't import"), findsOneWidget, reason: 'shoe size is not a column here');
      expect(find.textContaining('Clinic notes will be left out'), findsOneWidget);

      await tester.tap(find.text('Check 4 rows'));
      await tester.pumpAndSettle();

      // The empty name never reaches the database, nor does Ana's second row.
      expect(repo.calls.single.batchId, isNull);
      expect(repo.calls.single.rows.map((r) => r['row']), [2, 3]);
      expect(find.text('No name.'), findsOneWidget);
      expect(find.text('The same patient as row 2 of this file.'), findsOneWidget);
      expect(find.textContaining('On file: Maria Reyes'), findsOneWidget);

      await tester.tap(find.text('Add as new'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 2 patients'));
      await tester.pumpAndSettle();

      final real = repo.calls.last;
      expect(real.batchId, 'batch-1');
      expect(real.rows[1], containsPair('action', 'create'));
      expect(find.text('Import finished'), findsOneWidget);
      expect(find.text('Undo this import'), findsOneWidget);
    });

    testWidgets('visits: the file\'s doctors are matched to the roster first', (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appRoleProvider.overrideWithValue(AppRole.assistant),
          currentUserIdProvider.overrideWithValue('u1'),
          currentClinicProvider.overrideWithValue(const AsyncValue.data(_clinic)),
          canSeeClinicalNotesProvider.overrideWith((ref) async => false),
          currentClinicRoleProvider.overrideWith((ref) async => AppRole.assistant),
          healthRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: ImportFlow(spec: ImportSpec.of(ImportKind.visits), fileName: 'log.csv', rows: parseCsv(
            'Patient,Date,Dentist,Findings\n'
            'Ana Cruz,2023-01-10,Dra. Santos,Gingivitis\n'
            'Ben Lim,2023-01-11,Dr. Reyes,\n'
            'Cora Tan,2023-01-12,Dr. Lim,\n',
          )),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Doctors in this file'), findsOneWidget);
      expect(find.textContaining('Visit notes will be left out'), findsOneWidget);
      // Santos and Reyes (inactive) match; Lim does not, and holds the check.
      expect(find.text('Jose Reyes (inactive)'), findsOneWidget);
      expect(find.text('Match every doctor in the file to one on the roster.'), findsOneWidget);
      expect(find.byTooltip('Add as a former doctor'), findsNothing, reason: 'admins only');

      await tester.tap(find.text('Pick a doctor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Santos').last);
      await tester.pumpAndSettle();

      final before = repo.calls.length;
      await tester.tap(find.text('Check 3 rows'));
      await tester.pumpAndSettle();
      final sent = repo.calls[before];
      expect(sent.batchId, isNull);
      expect(sent.rows.map((r) => r['doctor_id']), ['d1', 'd2', 'd1']);
      expect(find.text('New visits'), findsOneWidget);
      expect(find.text('Import 3 visits'), findsOneWidget);
    });
  });
}

const _clinic = Clinic(
  id: 'c1',
  name: 'D-Touch',
  slug: 'dtouch',
  typeSlug: 'dental',
  typeName: 'Dental',
  chartKind: 'dental',
);

class _ImportRepo extends HealthRepository {
  _ImportRepo() : super(SupabaseClient('http://localhost', 'test-key'));

  final calls = <({List<Map<String, dynamic>> rows, String? batchId})>[];

  @override
  Future<String> startImport({
    required String clinicId,
    required String fileName,
    ImportKind kind = ImportKind.patients,
  }) async =>
      'batch-1';

  @override
  Future<List<Doctor>> fetchRoster(String clinicId) async => const [
        Doctor(id: 'd1', clinicId: 'c1', name: 'Maria Santos', specialty: '',
            availableWeekdays: [1], availableTimeSlots: []),
        Doctor(id: 'd2', clinicId: 'c1', name: 'Jose Reyes', specialty: '',
            availableWeekdays: [1], availableTimeSlots: [], isActive: false),
      ];

  @override
  Future<List<ImportRowResult>> importRows({
    required ImportKind kind,
    required String clinicId,
    required List<Map<String, dynamic>> rows,
    String? batchId,
  }) async {
    calls.add((rows: rows, batchId: batchId));
    return [
      for (final r in rows)
        if ((r['person'] as Map?)?['full_name'] == 'Maria Reyes' && r['action'] == null)
          ImportRowResult(
            row: r['row'] as int,
            outcome: ImportOutcome.duplicate,
            match: const ImportMatch(id: 'chart-2', name: 'Maria Reyes', phone: '09281234567'),
          )
        else
          ImportRowResult(row: r['row'] as int, outcome: ImportOutcome.created, patientId: 'x'),
    ];
  }
}
