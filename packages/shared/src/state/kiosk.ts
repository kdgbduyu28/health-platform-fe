/// The front desk tablet, handed to a patient to fill in their own form.
///
/// While one is active the router shows nothing but the form at
/// `/:clinic/kiosk` — every other URL, the browser's back button and a
/// reload included, lands there — until a staff PIN ends it.
export type KioskSession = {
  /// The clinic the form is for.
  slug: string;
  /// The chart being filled in. Null for a new patient, until they submit.
  patientId: string | null;
  /// The patient has sent the form and been asked to hand the tablet back.
  submitted: boolean;
};

export function kioskPath(session: KioskSession): string {
  return `/${session.slug}/kiosk`;
}

export function parseKioskSession(json: string | null): KioskSession | null {
  if (json == null) return null;
  try {
    const m = JSON.parse(json);
    if (typeof m?.slug !== 'string') return null;
    return { slug: m.slug, patientId: m.patient_id ?? null, submitted: m.submitted ?? false };
  } catch {
    return null;
  }
}
