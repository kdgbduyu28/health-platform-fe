import { parseTime, parseTimeOrNull } from '../util/dates';
import { type AppRole, appRoleFromWire } from './app_role';

type Json = Record<string, any>;

/// Where a staff code is in its life. Mirrors `staff_invites.status`.
///
///   open ──redeem──▶ pending ──approve──▶ approved
///     │                 │  └───reject───▶ rejected
///     └────revoke───────┴──────────────▶ revoked
export type StaffInviteStatus = 'open' | 'pending' | 'approved' | 'rejected' | 'revoked';

/// A single-use code an admin issued for one doctor or assistant, and the
/// request it became once someone entered it. Admin app only; RLS returns
/// these to the clinic's admins and nobody else.
export class StaffInvite {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly role: AppRole,
    readonly code: string,
    readonly status: StaffInviteStatus,
    readonly expiresAt: Date,
    /// Who the admin issued it for, e.g. "Dr Reyes".
    readonly label: string | null = null,
    /// Copied from the applicant's account when they entered the code.
    readonly redeemerName: string | null = null,
    readonly redeemerEmail: string | null = null,
    readonly redeemedAt: Date | null = null,
  ) {}

  static fromJson(json: Json): StaffInvite {
    return new StaffInvite(
      json.id,
      json.clinic_id,
      appRoleFromWire(json.role),
      json.code,
      json.status,
      parseTime(json.expires_at),
      json.label ?? null,
      json.redeemer_name ?? null,
      json.redeemer_email ?? null,
      parseTimeOrNull(json.redeemed_at),
    );
  }

  /// An open code past its expiry. The database leaves its status alone and
  /// simply refuses to redeem it.
  isExpired(now: Date = new Date()): boolean {
    return this.status === 'open' && this.expiresAt.getTime() <= now.getTime();
  }

  /// Who is asking, as the admin should see it.
  get applicant(): string {
    return this.redeemerName ?? this.redeemerEmail ?? 'Someone';
  }
}

/// The applicant's own view of a request: which clinic, and where it stands.
/// They are not a member yet, so this is all they can see of the clinic.
export class StaffRequest {
  constructor(
    readonly id: string,
    readonly clinicName: string,
    readonly role: AppRole,
    readonly status: StaffInviteStatus,
    readonly redeemedAt: Date | null = null,
  ) {}

  static fromJson(json: Json): StaffRequest {
    return new StaffRequest(json.id, json.clinic_name, appRoleFromWire(json.role), json.status, parseTimeOrNull(json.redeemed_at));
  }
}
