import type { IconName } from '../theme/icons';
import { parseTime, parseTimeOrNull } from '../util/dates';
import { parseMoney } from './money';
import { Patient } from './patient';

type Json = Record<string, any>;

/// Mirrors `public.invoice_status`. The database moves a bill along — see
/// 20260924120100_billing in health-platform-be:
///
///   draft ──issue──→ issued ⇄ paid
///                      └──void──→ void
///
/// A draft can also simply be deleted.
export type InvoiceStatus = 'draft' | 'issued' | 'paid' | 'void';
export const invoiceStatuses: readonly InvoiceStatus[] = ['draft', 'issued', 'paid', 'void'];
export const invoiceStatusMeta: Record<InvoiceStatus, { label: string; color: string }> = {
  draft: { label: 'Draft', color: '#757575' },
  issued: { label: 'Unpaid', color: '#E65100' },
  paid: { label: 'Paid', color: '#2E7D32' },
  void: { label: 'Void', color: '#C62828' },
};
export function invoiceStatusFromWire(value: string): InvoiceStatus {
  if ((invoiceStatuses as readonly string[]).includes(value)) return value as InvoiceStatus;
  throw new Error(`unknown invoice status: ${value}`);
}

/// Mirrors `public.payment_method`, in the order the desk picks from: the
/// common ones first.
export type PaymentMethod =
  | 'cash'
  | 'gcash'
  | 'bpi'
  | 'bdo'
  | 'qrph'
  | 'maya'
  | 'card'
  | 'bank_transfer'
  | 'hmo'
  | 'other';
export const paymentMethods: readonly PaymentMethod[] = [
  'cash',
  'gcash',
  'bpi',
  'bdo',
  'qrph',
  'maya',
  'card',
  'bank_transfer',
  'hmo',
  'other',
];
export const paymentMethodMeta: Record<PaymentMethod, { label: string; icon: IconName }> = {
  cash: { label: 'Cash', icon: 'payments' },
  gcash: { label: 'GCash', icon: 'phone-iphone' },
  bpi: { label: 'Bank · BPI', icon: 'account-balance' },
  bdo: { label: 'Bank · BDO', icon: 'account-balance' },
  qrph: { label: 'QR Ph', icon: 'qr-code-2' },
  maya: { label: 'Maya', icon: 'phone-iphone' },
  card: { label: 'Card', icon: 'credit-card' },
  bank_transfer: { label: 'Other bank', icon: 'account-balance' },
  hmo: { label: 'HMO', icon: 'health-and-safety' },
  other: { label: 'Other', icon: 'more-horiz' },
};
/// How most patients pay; the rest sit behind "More".
export const commonPaymentMethods: readonly PaymentMethod[] = ['cash', 'gcash', 'bpi', 'bdo', 'qrph'];

export function paymentMethodFromWire(value: string): PaymentMethod {
  if ((paymentMethods as readonly string[]).includes(value)) return value as PaymentMethod;
  throw new Error(`unknown payment method: ${value}`);
}

/// Whether the desk should ask for a reference (a GCash ref, an HMO approval
/// code) — cash has none.
export function wantsReference(m: PaymentMethod): boolean {
  return m !== 'cash';
}

/// One line on a bill.
export class InvoiceItem {
  constructor(
    readonly id: string,
    readonly description: string,
    readonly quantity: number,
    readonly unitPrice: number,
    readonly serviceId: string | null = null,
  ) {}

  get amount(): number {
    return this.quantity * this.unitPrice;
  }

  static fromJson(json: Json): InvoiceItem {
    return new InvoiceItem(json.id, json.description, json.quantity, parseMoney(json.unit_price), json.service_id ?? null);
  }
}

/// Money received against a bill. Never edited; an admin may void it.
export class Payment {
  constructor(
    readonly id: string,
    readonly amount: number,
    readonly method: PaymentMethod,
    readonly receivedAt: Date,
    readonly reference: string | null = null,
    readonly voidedAt: Date | null = null,
    readonly voidReason: string | null = null,
  ) {}

  get isVoid(): boolean {
    return this.voidedAt != null;
  }

  static fromJson(json: Json): Payment {
    return new Payment(
      json.id,
      parseMoney(json.amount),
      paymentMethodFromWire(json.method),
      parseTime(json.received_at),
      json.reference ?? null,
      parseTimeOrNull(json.voided_at),
      json.void_reason ?? null,
    );
  }
}

/// A bill from `public.invoices`, with its lines and payments.
///
/// Every total here is the database's: [subtotal] from the lines,
/// [amountPaid] from the payments that stand, [status] from both.
export class Invoice {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly patientId: string,
    readonly status: InvoiceStatus,
    readonly subtotal: number,
    readonly discountAmount: number,
    readonly total: number,
    readonly amountPaid: number,
    readonly createdAt: Date,
    readonly appointmentId: string | null = null,
    /// `INV-000042`; null until issued.
    readonly number: string | null = null,
    readonly discountReason: string | null = null,
    readonly notes: string | null = null,
    readonly issuedAt: Date | null = null,
    readonly voidedAt: Date | null = null,
    readonly voidReason: string | null = null,
    readonly items: InvoiceItem[] = [],
    readonly payments: Payment[] = [],
    /// The chart, when fetched embedded.
    readonly patient: Patient | null = null,
    /// The visit it bills, when fetched embedded.
    readonly visitService: string | null = null,
    readonly visitAt: Date | null = null,
    /// The visit's doctor's full name, when fetched embedded.
    readonly visitDoctor: string | null = null,
  ) {}

  get balance(): number {
    return this.total - this.amountPaid;
  }

  get isDraft(): boolean {
    return this.status === 'draft';
  }

  /// Still owes money.
  get isOpen(): boolean {
    return this.status === 'issued';
  }

  /// `INV-000042`, or "Draft" before it has a number.
  get label(): string {
    return this.number ?? 'Draft';
  }

  /// What a list shows it as: the visit's service, or its first line.
  get title(): string {
    return this.visitService ?? (this.items.length === 0 ? 'Bill' : this.items[0].description);
  }

  /// Standing payments, oldest first.
  get activePayments(): Payment[] {
    return this.payments.filter((p) => !p.isVoid);
  }

  /// Expects, optionally, these embeds:
  ///
  ///   invoices?select=*,items:invoice_items(*),payments(*),
  ///     patient:patients(*,person:persons(*)),
  ///     appointment:appointments(service_name,scheduled_at,
  ///       doctor:doctors(full_name))
  static fromJson(json: Json): Invoice {
    const visit = json.appointment as Json | null | undefined;
    const doctor = visit?.doctor as Json | null | undefined;
    const items = ((json.items ?? []) as Json[]).map(InvoiceItem.fromJson);
    const payments = ((json.payments ?? []) as Json[])
      .map(Payment.fromJson)
      .sort((a, b) => a.receivedAt.getTime() - b.receivedAt.getTime());
    return new Invoice(
      json.id,
      json.clinic_id,
      json.patient_id,
      invoiceStatusFromWire(json.status),
      parseMoney(json.subtotal),
      parseMoney(json.discount_amount),
      parseMoney(json.total),
      parseMoney(json.amount_paid),
      parseTime(json.created_at),
      json.appointment_id ?? null,
      json.number ?? null,
      json.discount_reason ?? null,
      json.notes ?? null,
      parseTimeOrNull(json.issued_at),
      parseTimeOrNull(json.voided_at),
      json.void_reason ?? null,
      items,
      payments,
      json.patient == null ? null : Patient.fromJson(json.patient),
      visit?.service_name ?? null,
      parseTimeOrNull(visit?.scheduled_at),
      doctor?.full_name ?? null,
    );
  }
}

/// Money in and money owed at a clinic over some days, from
/// `public.billing_summary`.
export class BillingSummary {
  constructor(
    readonly collected: number,
    readonly byMethod: Map<PaymentMethod, number>,
    readonly billed: number,
    /// Owed on issued bills right now, whatever the range.
    readonly outstanding: number,
    readonly unpaidCount: number,
    readonly draftCount: number,
  ) {}

  static fromJson(json: Json): BillingSummary {
    const methods = (json.by_method as Json | null | undefined) ?? {};
    return new BillingSummary(
      parseMoney(json.collected),
      new Map(Object.entries(methods).map(([k, v]) => [paymentMethodFromWire(k), parseMoney(v)])),
      parseMoney(json.billed),
      parseMoney(json.outstanding),
      json.unpaid_count ?? 0,
      json.draft_count ?? 0,
    );
  }
}
