import 'package:flutter/material.dart';

import 'money.dart';
import 'patient.dart';

/// Mirrors `public.invoice_status`. The database moves a bill along — see
/// 20260924120100_billing in health-platform-be:
///
///   draft ──issue──→ issued ⇄ paid
///                      └──void──→ voided
///
/// A draft can also simply be deleted.
enum InvoiceStatus {
  draft('draft'),
  issued('issued'),
  paid('paid'),
  voided('void');

  const InvoiceStatus(this.wire);

  final String wire;

  static InvoiceStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value);

  String get displayName => switch (this) {
        draft => 'Draft',
        issued => 'Unpaid',
        paid => 'Paid',
        voided => 'Void',
      };

  Color get color => switch (this) {
        draft => const Color(0xFF757575),
        issued => const Color(0xFFE65100),
        paid => const Color(0xFF2E7D32),
        voided => const Color(0xFFC62828),
      };
}

/// Mirrors `public.payment_method`.
enum PaymentMethod {
  cash('cash', 'Cash', Icons.payments_outlined),
  gcash('gcash', 'GCash', Icons.phone_iphone),
  maya('maya', 'Maya', Icons.phone_iphone),
  card('card', 'Card', Icons.credit_card),
  bankTransfer('bank_transfer', 'Bank transfer', Icons.account_balance_outlined),
  hmo('hmo', 'HMO', Icons.health_and_safety_outlined),
  other('other', 'Other', Icons.more_horiz);

  const PaymentMethod(this.wire, this.displayName, this.icon);

  final String wire;
  final String displayName;
  final IconData icon;

  static PaymentMethod fromWire(String value) =>
      values.firstWhere((m) => m.wire == value);

  /// Whether the desk should ask for a reference (a GCash ref, an HMO
  /// approval code) — cash has none.
  bool get wantsReference => this != cash;
}

/// One line on a bill.
class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.serviceId,
  });

  final String id;
  final String description;
  final int quantity;
  final double unitPrice;
  final String? serviceId;

  double get amount => quantity * unitPrice;

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
        id: json['id'] as String,
        description: json['description'] as String,
        quantity: json['quantity'] as int,
        unitPrice: parseMoney(json['unit_price']),
        serviceId: json['service_id'] as String?,
      );
}

/// Money received against a bill. Never edited; an admin may void it.
class Payment {
  const Payment({
    required this.id,
    required this.amount,
    required this.method,
    required this.receivedAt,
    this.reference,
    this.voidedAt,
    this.voidReason,
  });

  final String id;
  final double amount;
  final PaymentMethod method;
  final DateTime receivedAt;
  final String? reference;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get isVoid => voidedAt != null;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String,
        amount: parseMoney(json['amount']),
        method: PaymentMethod.fromWire(json['method'] as String),
        receivedAt: DateTime.parse(json['received_at'] as String).toLocal(),
        reference: json['reference'] as String?,
        voidedAt: _time(json['voided_at']),
        voidReason: json['void_reason'] as String?,
      );
}

/// A bill from `public.invoices`, with its lines and payments.
///
/// Every total here is the database's: [subtotal] from the lines,
/// [amountPaid] from the payments that stand, [status] from both.
class Invoice {
  const Invoice({
    required this.id,
    required this.clinicId,
    required this.patientId,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
    required this.amountPaid,
    required this.createdAt,
    this.appointmentId,
    this.number,
    this.discountReason,
    this.notes,
    this.issuedAt,
    this.voidedAt,
    this.voidReason,
    this.items = const [],
    this.payments = const [],
    this.patient,
    this.visitService,
    this.visitAt,
  });

  final String id;
  final String clinicId;
  final String patientId;
  final String? appointmentId;

  /// `INV-000042`; null until issued.
  final String? number;
  final InvoiceStatus status;
  final double subtotal;
  final double discountAmount;
  final String? discountReason;
  final double total;
  final double amountPaid;
  final String? notes;
  final DateTime createdAt;
  final DateTime? issuedAt;
  final DateTime? voidedAt;
  final String? voidReason;
  final List<InvoiceItem> items;
  final List<Payment> payments;

  /// The chart, when fetched embedded.
  final Patient? patient;

  /// The visit it bills, when fetched embedded.
  final String? visitService;
  final DateTime? visitAt;

  double get balance => total - amountPaid;

  bool get isDraft => status == InvoiceStatus.draft;

  /// Still owes money.
  bool get isOpen => status == InvoiceStatus.issued;

  /// `INV-000042`, or "Draft" before it has a number.
  String get label => number ?? 'Draft';

  /// What a list shows it as: the visit's service, or its first line.
  String get title =>
      visitService ?? (items.isEmpty ? 'Bill' : items.first.description);

  /// Standing payments, oldest first.
  List<Payment> get activePayments =>
      [for (final p in payments) if (!p.isVoid) p];

  /// Expects, optionally, these embeds:
  ///
  ///   invoices?select=*,items:invoice_items(*),payments(*),
  ///     patient:patients(*,person:persons(*)),
  ///     appointment:appointments(service_name,scheduled_at)
  factory Invoice.fromJson(Map<String, dynamic> json) {
    final visit = json['appointment'] as Map<String, dynamic>?;
    final items = [
      for (final i in (json['items'] as List<dynamic>? ?? const []))
        InvoiceItem.fromJson(i as Map<String, dynamic>),
    ];
    final payments = [
      for (final p in (json['payments'] as List<dynamic>? ?? const []))
        Payment.fromJson(p as Map<String, dynamic>),
    ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return Invoice(
      id: json['id'] as String,
      clinicId: json['clinic_id'] as String,
      patientId: json['patient_id'] as String,
      appointmentId: json['appointment_id'] as String?,
      number: json['number'] as String?,
      status: InvoiceStatus.fromWire(json['status'] as String),
      subtotal: parseMoney(json['subtotal']),
      discountAmount: parseMoney(json['discount_amount']),
      discountReason: json['discount_reason'] as String?,
      total: parseMoney(json['total']),
      amountPaid: parseMoney(json['amount_paid']),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      issuedAt: _time(json['issued_at']),
      voidedAt: _time(json['voided_at']),
      voidReason: json['void_reason'] as String?,
      items: items,
      payments: payments,
      patient: json['patient'] == null
          ? null
          : Patient.fromJson(json['patient'] as Map<String, dynamic>),
      visitService: visit?['service_name'] as String?,
      visitAt: _time(visit?['scheduled_at']),
    );
  }
}

/// Money in and money owed at a clinic over some days, from
/// `public.billing_summary`.
class BillingSummary {
  const BillingSummary({
    required this.collected,
    required this.byMethod,
    required this.billed,
    required this.outstanding,
    required this.unpaidCount,
    required this.draftCount,
  });

  final double collected;
  final Map<PaymentMethod, double> byMethod;
  final double billed;

  /// Owed on issued bills right now, whatever the range.
  final double outstanding;
  final int unpaidCount;
  final int draftCount;

  factory BillingSummary.fromJson(Map<String, dynamic> json) {
    final methods = json['by_method'] as Map<String, dynamic>? ?? const {};
    return BillingSummary(
      collected: parseMoney(json['collected']),
      byMethod: {
        for (final e in methods.entries)
          PaymentMethod.fromWire(e.key): parseMoney(e.value),
      },
      billed: parseMoney(json['billed']),
      outstanding: parseMoney(json['outstanding']),
      unpaidCount: json['unpaid_count'] as int? ?? 0,
      draftCount: json['draft_count'] as int? ?? 0,
    );
  }
}

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
