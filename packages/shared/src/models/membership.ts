import { type AppRole, appRoleFromWire, isGrantedBy, roleDisplayName } from './app_role';
import type { Patient } from './patient';

type Json = Record<string, any>;

/// A row of `clinic_memberships`: the role one account holds at ONE clinic.
///
/// Roles are per clinic, not per account, so the same person can be an admin
/// at their own practice and a doctor at another. The name and email are only
/// present when the profile was embedded (the admin's staff list).
export class ClinicMembership {
  constructor(
    readonly profileId: string,
    readonly clinicId: string,
    readonly role: AppRole,
    /// A branch admin: an admin inside this clinic, but unable to manage its
    /// admins or to be an admin anywhere else. Only ever true for admins.
    readonly branchLocked: boolean = false,
    readonly fullName: string | null = null,
    readonly email: string | null = null,
  ) {}

  get isFullAdmin(): boolean {
    return this.role === 'admin' && !this.branchLocked;
  }

  get roleLabel(): string {
    return this.branchLocked ? 'Branch admin' : roleDisplayName(this.role);
  }

  static fromJson(json: Json): ClinicMembership {
    const profile = json.profile as Json | null | undefined;
    return new ClinicMembership(
      json.profile_id,
      json.clinic_id,
      appRoleFromWire(json.role),
      json.branch_locked ?? false,
      profile?.full_name ?? null,
      profile?.email ?? null,
    );
  }
}

/// The clinics [app] may be used at: those holding one of the patient's
/// charts in the patient app, those with a membership that grants the app in
/// the staff apps.
export function eligibleClinicIds(app: AppRole, charts: readonly Patient[], memberships: readonly ClinicMembership[]): string[] {
  return app === 'patient' ? charts.map((c) => c.clinicId) : memberships.filter((m) => isGrantedBy(app, m.role)).map((m) => m.clinicId);
}
