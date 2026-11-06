import type { IconName } from '../theme/icons';
import { parseDayOrNull, parseTime, parseTimeOrNull } from '../util/dates';
import { parseMoney } from './money';

type Json = Record<string, any>;

/// Mirrors `treatment_estimates.status` — see 20261106120000 in
/// health-platform-be.
///
///   draft ──send──→ sent ──→ accepted (──→ billed) | declined
///   and void, from anything but void.
export type EstimateStatus = 'draft' | 'sent' | 'accepted' | 'declined' | 'void';

export const estimateStatusMeta: Record<EstimateStatus, { label: string; color: string; icon: IconName }> = {
  draft: { label: 'Draft', color: '#757575', icon: 'edit-note' },
  sent: { label: 'Waiting for patient', color: '#EF6C00', icon: 'hourglass-bottom' },
  accepted: { label: 'Accepted', color: '#2E7D32', icon: 'check-circle-outline' },
  declined: { label: 'Declined', color: '#C62828', icon: 'highlight-off' },
  void: { label: 'Void', color: '#757575', icon: 'block' },
};

export function estimateStatusFromWire(value: string): EstimateStatus {
  if (value in estimateStatusMeta) return value as EstimateStatus;
  throw new Error(`unknown estimate status: ${value}`);
}

/// One priced line. [dentalEntryId] ties it to the planned chart entry it
/// prices, if any.
export type EstimateLine = {
  id?: string;
  serviceId: string | null;
  dentalEntryId: string | null;
  tooth: number | null;
  description: string;
  quantity: number;
  unitPrice: number;
};

export function lineAmount(l: EstimateLine): number {
  return l.quantity * l.unitPrice;
}

export class TreatmentEstimate {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly patientId: string,
    readonly status: EstimateStatus,
    readonly title: string | null,
    readonly notes: string | null,
    readonly validUntil: Date | null,
    readonly total: number,
    readonly createdAt: Date,
    readonly lines: EstimateLine[],
    readonly sentAt: Date | null = null,
    readonly decidedAt: Date | null = null,
    readonly voidReason: string | null = null,
    /// The draft bill an accepted estimate became.
    readonly invoiceId: string | null = null,
  ) {}

  /// The row and its lines, in order.
  static readonly select = '*, items:estimate_items(*)';

  get isDraft(): boolean {
    return this.status === 'draft';
  }

  /// Past its validity: no longer open to a decision.
  expired(today: Date = new Date()): boolean {
    if (this.validUntil == null) return false;
    const end = new Date(this.validUntil.getFullYear(), this.validUntil.getMonth(), this.validUntil.getDate() + 1);
    return today.getTime() >= end.getTime();
  }

  /// Waiting on a yes or no, and still in time for one.
  canDecide(today: Date = new Date()): boolean {
    return this.status === 'sent' && !this.expired(today);
  }

  get canBill(): boolean {
    return this.status === 'accepted' && this.invoiceId == null;
  }

  static fromJson(json: Json): TreatmentEstimate {
    const items = ((json.items as Json[] | null) ?? [])
      .slice()
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0) || String(a.created_at).localeCompare(String(b.created_at)));
    return new TreatmentEstimate(
      json.id,
      json.clinic_id,
      json.patient_id,
      estimateStatusFromWire(json.status),
      json.title ?? null,
      json.notes ?? null,
      parseDayOrNull(json.valid_until),
      parseMoney(json.total),
      parseTime(json.created_at),
      items.map((i) => ({
        id: i.id,
        serviceId: i.service_id ?? null,
        dentalEntryId: i.dental_entry_id ?? null,
        tooth: i.tooth == null ? null : Number(i.tooth),
        description: i.description,
        quantity: Number(i.quantity ?? 1),
        unitPrice: parseMoney(i.unit_price),
      })),
      parseTimeOrNull(json.sent_at),
      parseTimeOrNull(json.decided_at),
      json.void_reason ?? null,
      json.invoice_id ?? null,
    );
  }
}
