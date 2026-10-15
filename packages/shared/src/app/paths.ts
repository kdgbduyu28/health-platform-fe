// The app's URLs as plain functions, free of the router, so the redirect
// rules that use them can be tested on their own.

import { type AppRole, homeSubpath } from '../models/app_role';

/// Slugs that name pages of their own rather than a clinic. All are reserved
/// in the database too.
export const reservedSlugs = new Set(['not-found', 'privacy', 'terms']);

/// The clinic slug in a path — `dtouchdental` in `/dtouchdental/book` — or
/// null outside any clinic (`/`, `/not-found`).
export function clinicSlugOf(pathname: string): string | null {
  const first = pathname.split('/').find((s) => s !== '');
  if (first == null) return null;
  const slug = decodeURIComponent(first).toLowerCase();
  return reservedSlugs.has(slug) ? null : slug;
}

/// Where [app] lands at the clinic with [slug].
export function clinicHome(slug: string, app: AppRole): string {
  return `/${slug}${homeSubpath(app)}`;
}

/// Only paths inside this app: `?next=https://evil.example` must not turn a
/// sign-in link into an open redirect.
export function safeNext(next: string | null | undefined): string | null {
  if (next == null || !next.startsWith('/') || next.startsWith('//')) return null;
  return next;
}
