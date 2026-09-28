import 'package:api_sdk/api_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the desk picks from cash, GCash, BPI, BDO and QR Ph first', () {
    expect(PaymentMethod.common.map((m) => m.wire),
        ['cash', 'gcash', 'bpi', 'bdo', 'qrph']);
    for (final m in PaymentMethod.values) {
      expect(PaymentMethod.fromWire(m.wire), m);
    }
  });

  test('a ledger summary reads the database\'s figures as they are', () {
    final s = LedgerSummary.fromJson({
      'gross': 1500,
      'discounts': '0.00',
      'bill_count': 1,
      'paid': 500,
      'payment_count': 1,
      'by_method': {'bpi': 500},
      'pending': 1000,
      'expenses': 200,
      'by_category': {'Supplies': 200},
      'net': 300,
      'outstanding': 1000,
      'unpaid_count': 1,
      'draft_total': 0,
      'draft_count': 0,
    });
    expect(s.gross, 1500);
    expect(s.byMethod, {PaymentMethod.bpi: 500});
    expect(s.byCategory, {'Supplies': 200});
    expect(s.net, 300);
  });

  test('a ledger entry is a payment in or an expense out', () {
    final e = LedgerEntry.fromJson({
      'kind': 'expense',
      'id': 'e1',
      'happened_at': '2026-09-23T04:00:00Z',
      'amount': '200.00',
      'method': 'cash',
      'reference': null,
      'title': 'Supplies',
      'detail': 'Gloves',
      'invoice_id': null,
      'voided': false,
      'void_reason': null,
    });
    expect(e.isExpense, isTrue);
    expect(e.amount, 200);
    expect(e.method, PaymentMethod.cash);
  });
}
