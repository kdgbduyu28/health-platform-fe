import { format } from 'date-fns';

import { parseDay } from '../util/dates';

/// Who runs the platform, and where privacy and support requests go. The
/// same address serves as the Data Protection Officer's. Set
/// EXPO_PUBLIC_LEGAL_OPERATOR / EXPO_PUBLIC_LEGAL_EMAIL at build time to
/// change them.
export const LegalContact = {
  operator: process.env.EXPO_PUBLIC_LEGAL_OPERATOR || 'D-Touch Dental Clinic',
  email: process.env.EXPO_PUBLIC_LEGAL_EMAIL || 'dtouchdental@gmail.com',
};

/// A policy the apps show and people agree to: the Privacy Policy, the Terms
/// and Conditions.
///
/// [version] is the document's date. Each account's acknowledgement records
/// it (health-platform-be, policy_acknowledgements), so bump it whenever the
/// wording changes what someone agreed to.
export type LegalDocument = {
  /// As the database names it: `privacy` or `terms`.
  id: string;
  title: string;
  version: string;
  intro: string;
  sections: LegalSection[];
};

/// A heading and its paragraphs. A paragraph starting with `- ` is drawn as a
/// bullet.
export type LegalSection = { heading: string; body: string[] };

/// `September 30, 2026`.
export function legalDated(document: LegalDocument): string {
  return format(parseDay(document.version), 'MMMM d, y');
}
