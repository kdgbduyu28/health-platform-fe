import 'invoice.dart';
import 'money.dart';

/// A clinic's money over some days, from `public.ledger_summary` — see
/// 20260930120000_payments_ledger in health-platform-be.
class LedgerSummary {
  const LedgerSummary({
    required this.gross,
    required this.discounts,
    required this.billCount,
    required this.paid,
    required this.paymentCount,
    required this.byMethod,
    required this.pending,
    required this.expenses,
    required this.byCategory,
    required this.net,
    required this.outstanding,
    required this.unpaidCount,
    required this.draftTotal,
    required this.draftCount,
  });

  /// What the bills issued in the range came to, after discounts.
  final double gross;
  final double discounts;
  final int billCount;

  /// Money received in the range, whichever bill it was for.
  final double paid;
  final int paymentCount;
  final Map<PaymentMethod, double> byMethod;

  /// What the bills issued in the range still owe.
  final double pending;
  final double expenses;
  final Map<String, double> byCategory;

  /// [paid] − [expenses].
  final double net;

  /// Everything still owed, now, whatever the range.
  final double outstanding;
  final int unpaidCount;

  /// Bills drafted (visits done) but not yet issued, now.
  final double draftTotal;
  final int draftCount;

  factory LedgerSummary.fromJson(Map<String, dynamic> json) {
    final methods = json['by_method'] as Map<String, dynamic>? ?? const {};
    final categories = json['by_category'] as Map<String, dynamic>? ?? const {};
    return LedgerSummary(
      gross: parseMoney(json['gross']),
      discounts: parseMoney(json['discounts']),
      billCount: json['bill_count'] as int? ?? 0,
      paid: parseMoney(json['paid']),
      paymentCount: json['payment_count'] as int? ?? 0,
      byMethod: {
        for (final e in methods.entries)
          PaymentMethod.fromWire(e.key): parseMoney(e.value),
      },
      pending: parseMoney(json['pending']),
      expenses: parseMoney(json['expenses']),
      byCategory: {
        for (final e in categories.entries) e.key: parseMoney(e.value),
      },
      net: parseMoney(json['net']),
      outstanding: parseMoney(json['outstanding']),
      unpaidCount: json['unpaid_count'] as int? ?? 0,
      draftTotal: parseMoney(json['draft_total']),
      draftCount: json['draft_count'] as int? ?? 0,
    );
  }
}

enum LedgerEntryKind { payment, expense }

/// One payment in or expense out, from `public.ledger_entries`.
class LedgerEntry {
  const LedgerEntry({
    required this.kind,
    required this.id,
    required this.at,
    required this.amount,
    required this.method,
    required this.title,
    required this.voided,
    this.reference,
    this.detail,
    this.invoiceId,
    this.voidReason,
  });

  final LedgerEntryKind kind;
  final String id;

  /// When a payment was received; the day (at noon) an expense was spent.
  final DateTime at;
  final double amount;
  final PaymentMethod method;
  final String? reference;

  /// The patient, or the expense's category.
  final String title;

  /// The bill number, or the expense's description.
  final String? detail;
  final String? invoiceId;
  final bool voided;
  final String? voidReason;

  bool get isExpense => kind == LedgerEntryKind.expense;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        kind: json['kind'] == 'expense'
            ? LedgerEntryKind.expense
            : LedgerEntryKind.payment,
        id: json['id'] as String,
        at: DateTime.parse(json['happened_at'] as String).toLocal(),
        amount: parseMoney(json['amount']),
        method: PaymentMethod.fromWire(json['method'] as String),
        reference: json['reference'] as String?,
        title: json['title'] as String,
        detail: json['detail'] as String?,
        invoiceId: json['invoice_id'] as String?,
        voided: json['voided'] as bool? ?? false,
        voidReason: json['void_reason'] as String?,
      );
}

/// What the desk suggests when recording an expense. Free text in the
/// database: a clinic can use its own.
const expenseCategories = [
  'Supplies',
  'Lab fees',
  'Rent',
  'Salaries',
  'Utilities',
  'Equipment',
  'Maintenance',
  'Marketing',
  'Other',
];
