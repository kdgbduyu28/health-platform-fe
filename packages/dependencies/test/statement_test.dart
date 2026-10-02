import 'package:api_sdk/api_sdk.dart';
import 'package:api_sdk/src/billing/statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _clinic = Clinic(
  id: 'c1',
  name: 'D-Touch Dental Clinic',
  slug: 'dtouchdental',
  typeSlug: 'dental',
  typeName: 'Dental',
  address: 'Quezon City',
  contactPhone: '0917 000 0000',
  logoUrl: 'asset:assets/brand/dtouch_mark.png',
);

const _patient = Patient(
  id: 'chart-1',
  personId: 'person-1',
  clinicId: 'c1',
  name: 'Ana <Cruz>',
  phone: '0917 555 0101',
  email: '',
  chartNumber: 'A-12',
);

Invoice _bill(Map<String, dynamic> over) => Invoice.fromJson({
      'id': 'inv-1',
      'clinic_id': 'c1',
      'patient_id': 'chart-1',
      'status': 'issued',
      'number': 'INV-000001',
      'subtotal': 2500,
      'discount_amount': 0,
      'total': 2500,
      'amount_paid': 0,
      'created_at': '2026-09-20T02:00:00Z',
      'issued_at': '2026-09-20T03:00:00Z',
      'items': [
        {
          'id': 'i1',
          'description': 'Oral prophylaxis',
          'quantity': 1,
          'unit_price': 1500,
        },
        {
          'id': 'i2',
          'description': 'Fluoride',
          'quantity': 2,
          'unit_price': 500,
        },
      ],
      'payments': const [],
      'appointment': {
        'service_name': 'Cleaning',
        'scheduled_at': '2026-09-20T01:00:00Z',
        'doctor': {'full_name': 'Maria Santos'},
      },
      ...over,
    });

void main() {
  test('the bill query reads the visit\'s doctor', () {
    expect(_bill({}).visitDoctor, 'Maria Santos');
  });

  test('a statement lists every line, discount, payment and balance', () {
    final paid = _bill({
      'id': 'inv-2',
      'number': 'INV-000002',
      'status': 'issued',
      'subtotal': 2500,
      'discount_amount': 500,
      'discount_reason': 'Senior',
      'total': 2000,
      'amount_paid': 1200,
      'payments': [
        {
          'id': 'p1',
          'amount': 1200,
          'method': 'gcash',
          'reference': '99887766',
          'received_at': '2026-09-21T03:00:00Z',
        },
        {
          'id': 'p2',
          'amount': 300,
          'method': 'cash',
          'received_at': '2026-09-21T04:00:00Z',
          'voided_at': '2026-09-21T05:00:00Z',
        },
      ],
    });
    final html = buildStatementHtml(
      clinic: _clinic,
      patient: _patient,
      invoices: [paid, _bill({})],
      printedAt: DateTime(2026, 9, 30, 10),
    );

    expect(html, contains('D-Touch Dental Clinic'));
    expect(html, contains('Chart no. A-12'));
    expect(html, contains('Statement of account'));
    // Names are escaped, not taken as markup.
    expect(html, contains('Ana &lt;Cruz&gt;'));
    expect(html, isNot(contains('Ana <Cruz>')));
    // The file name the PDF is offered under.
    expect(html, contains('<title>Statement - Ana &lt;Cruz&gt; - 2026-09-30</title>'));
    // Lines, visit and doctor.
    expect(html, contains('Oral prophylaxis'));
    expect(html, contains('₱1,000'));
    expect(html, contains('Dr. Maria Santos'));
    // Discount and the payment that stands, not the voided one.
    expect(html, contains('Discount (Senior)'));
    expect(html, contains('GCash · ref 99887766'));
    expect(html, isNot(contains('₱300')));
    // Totals over both bills: 2000 + 2500 charged, 1200 paid, 3300 due.
    expect(html, contains('<td>Total charges (2 bills)</td><td>₱4,500</td>'));
    expect(html, contains('<td>Total paid</td><td>₱1,200</td>'));
    expect(html, contains('<td>Balance due</td><td>₱3,300</td>'));
    expect(html, contains('not an official receipt'));
    // The bundled logo loads from the web build's assets.
    expect(html,
        contains('src="assets/packages/api_sdk/assets/brand/dtouch_mark.png"'));
  });

  test('a fully paid statement is a payment summary; drafts are estimates, '
      'voided bills are left out', () {
    final paid = _bill({'status': 'paid', 'amount_paid': 2500});
    expect(
      buildStatementHtml(clinic: _clinic, patient: _patient, invoices: [paid]),
      contains('Payment summary'),
    );

    final draft = _bill({'id': 'd', 'status': 'draft', 'number': null});
    final voided = _bill({'id': 'v', 'status': 'void', 'number': 'INV-000009'});
    final html = buildStatementHtml(
        clinic: _clinic, patient: _patient, invoices: [draft, voided]);
    expect(html, contains('Estimate'));
    expect(html, contains('Not yet issued'));
    expect(html, contains('may change'));
    expect(html, isNot(contains('INV-000009')));
  });

  testWidgets('the sheet offers bills but not voided ones, newest ticked',
      (tester) async {
    final bills = [
      _bill({'id': 'new', 'number': 'INV-000003'}),
      _bill({'id': 'old', 'number': 'INV-000002'}),
      _bill({'id': 'gone', 'number': 'INV-000001', 'status': 'void'}),
    ];
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPrintStatementSheet(context,
                  patient: _patient, invoices: bills),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('All visits (2)'), findsOneWidget);
    expect(find.textContaining('INV-000001'), findsNothing);
    expect(find.text('Print 1 visit · ₱2,500'), findsOneWidget);

    await tester.tap(find.text('All visits (2)'));
    await tester.pump();
    expect(find.text('Print 2 visits · ₱5,000'), findsOneWidget);

    await tester.tap(find.text('All visits (2)'));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.ancestor(
                of: find.text('Print'), matching: find.byWidgetPredicate((w) => w is FilledButton)))
            .onPressed,
        isNull);
  });
}
