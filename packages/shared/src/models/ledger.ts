import { parseTime } from '../util/dates';
import { type PaymentMethod, paymentMethodFromWire } from './invoice';
import { parseMoney } from './money';

type Json = Record<string, any>;

/// A clinic's money over some days, from `public.ledger_summary` — see
/// 20260930120000_payments_ledger in health-platform-be.
export class LedgerSummary {
  constructor(
    /// What the bills issued in the range came to, after discounts.
    readonly gross: number,
    readonly discounts: number,
    readonly billCount: number,
    /// Money received in the range, whichever bill it was for.
    readonly paid: number,
    readonly paymentCount: number,
    readonly byMethod: Map<PaymentMethod, number>,
    /// What the bills issued in the range still owe.
    readonly pending: number,
    readonly expenses: number,
    readonly byCategory: Map<string, number>,
    /// [paid] − [expenses].
    readonly net: number,
    /// Everything still owed, now, whatever the range.
    readonly outstanding: number,
    readonly unpaidCount: number,
    /// Bills drafted (visits done) but not yet issued, now.
    readonly draftTotal: number,
    readonly draftCount: number,
  ) {}

  static fromJson(json: Json): LedgerSummary {
    const methods = (json.by_method as Json | null | undefined) ?? {};
    const categories = (json.by_category as Json | null | undefined) ?? {};
    return new LedgerSummary(
      parseMoney(json.gross),
      parseMoney(json.discounts),
      json.bill_count ?? 0,
      parseMoney(json.paid),
      json.payment_count ?? 0,
      new Map(Object.entries(methods).map(([k, v]) => [paymentMethodFromWire(k), parseMoney(v)])),
      parseMoney(json.pending),
      parseMoney(json.expenses),
      new Map(Object.entries(categories).map(([k, v]) => [k, parseMoney(v)])),
      parseMoney(json.net),
      parseMoney(json.outstanding),
      json.unpaid_count ?? 0,
      parseMoney(json.draft_total),
      json.draft_count ?? 0,
    );
  }
}

export type LedgerEntryKind = 'payment' | 'expense';

/// One payment in or expense out, from `public.ledger_entries`.
export class LedgerEntry {
  constructor(
    readonly kind: LedgerEntryKind,
    readonly id: string,
    /// When a payment was received; the day (at noon) an expense was spent.
    readonly at: Date,
    readonly amount: number,
    readonly method: PaymentMethod,
    /// The patient, or the expense's category.
    readonly title: string,
    readonly voided: boolean,
    readonly reference: string | null = null,
    /// The bill number, or the expense's description.
    readonly detail: string | null = null,
    readonly invoiceId: string | null = null,
    readonly voidReason: string | null = null,
  ) {}

  get isExpense(): boolean {
    return this.kind === 'expense';
  }

  static fromJson(json: Json): LedgerEntry {
    return new LedgerEntry(
      json.kind === 'expense' ? 'expense' : 'payment',
      json.id,
      parseTime(json.happened_at),
      parseMoney(json.amount),
      paymentMethodFromWire(json.method),
      json.title,
      json.voided ?? false,
      json.reference ?? null,
      json.detail ?? null,
      json.invoice_id ?? null,
      json.void_reason ?? null,
    );
  }
}

/// What the desk suggests when recording an expense. Free text in the
/// database: a clinic can use its own.
export const expenseCategories = [
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
