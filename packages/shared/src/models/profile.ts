type Json = Record<string, any>;

/// Initials for an avatar: first and last word, or the one word's first
/// letter, or `?` for nothing.
export function initialsOf(name: string): string {
  const trimmed = name.trim();
  if (trimmed === '') return '?';
  const parts = trimmed.split(/\s+/);
  if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  return parts[0][0].toUpperCase();
}

/// A row from `public.profiles` — the 1:1 companion to the `auth.users`
/// record for the signed-in account.
///
/// A profile is just an account. What it may do is decided per clinic: by a
/// membership for staff (see ClinicMembership) or by holding a chart there for
/// patients.
export class Profile {
  constructor(
    readonly id: string,
    readonly fullName: string,
    readonly email: string | null = null,
    readonly phone: string | null = null,
  ) {}

  static fromJson(json: Json): Profile {
    return new Profile(json.id, json.full_name, json.email ?? null, json.phone ?? null);
  }

  get initials(): string {
    const parts = this.fullName.trim().split(/\s+/);
    if (parts.length >= 2) return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
    return this.fullName === '' ? '?' : this.fullName[0].toUpperCase();
  }

  /// The greeting name — "Juan" out of "Juan dela Cruz".
  get firstName(): string {
    return this.fullName.trim().split(/\s+/)[0];
  }
}
