/// Mirrors `public.app_role`, and names the four apps.
///
/// A role is held per clinic, on `clinic_memberships` — never per account — so
/// one person can be an admin at one clinic and a doctor at another.
/// `patient` is never a membership role: a patient is recognised by holding a
/// chart at the clinic instead. The database, not the client, decides all of
/// this.
export type AppRole = 'patient' | 'doctor' | 'assistant' | 'admin';

export const appRoles: readonly AppRole[] = ['patient', 'doctor', 'assistant', 'admin'];

export function appRoleFromWire(value: string): AppRole {
  if ((appRoles as readonly string[]).includes(value)) return value as AppRole;
  throw new Error(`unknown app role: ${value}`);
}

export function isStaffRole(role: AppRole): boolean {
  return role !== 'patient';
}

/// Whether new staff join this app with a single-use code from an admin.
/// Admins are added by email instead, by a full admin.
export function takesStaffCodes(role: AppRole): boolean {
  return role === 'doctor' || role === 'assistant';
}

/// Whether this app adds new patients — and so can hand the tablet to one to
/// fill in their own form. Every staff app does; mirrors
/// `private.can_add_patients`. Importing them from a file is narrower (front
/// desk and admins), and is offered only where an app passes `onOpenData`.
export function registersPatients(role: AppRole): boolean {
  return isStaffRole(role);
}

/// Whether a membership with this role may read and write clinical notes.
/// Mirrors `private.is_clinician` in the database.
export function seesClinicalNotes(role: AppRole): boolean {
  return role === 'doctor' || role === 'admin';
}

/// Where this app lands inside a clinic, under `/:clinic`. The bare `/:clinic`
/// is the public page in the patient app and redirects here in the others.
export function homeSubpath(role: AppRole): string {
  switch (role) {
    case 'patient':
      return '/home';
    case 'doctor':
      return '/schedule';
    case 'assistant':
      return '/check-in';
    case 'admin':
      return '/dashboard';
  }
}

export function roleDisplayName(role: AppRole): string {
  switch (role) {
    case 'patient':
      return 'Patient';
    case 'doctor':
      return 'Doctor';
    case 'assistant':
      return 'Assistant';
    case 'admin':
      return 'Administrator';
  }
}

/// Whether a membership with [membershipRole] lets its holder use the app
/// named by [app].
///
/// Admins may run the front desk — the database lets them register walk-ins
/// too — so the assistant app accepts them. The doctor app does not: it is
/// built around the signed-in doctor's own roster row.
export function isGrantedBy(app: AppRole, membershipRole: AppRole): boolean {
  switch (app) {
    case 'patient':
      return false;
    case 'doctor':
      return membershipRole === 'doctor';
    case 'assistant':
      return membershipRole === 'assistant' || membershipRole === 'admin';
    case 'admin':
      return membershipRole === 'admin';
  }
}
