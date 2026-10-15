import type { IconName } from '../theme/icons';

type Json = Record<string, any>;

/// A clinic tenant, as the signed-in user is allowed to see it.
///
/// Everything the apps used to compile in per flavor — name, colour, logo, the
/// vertical's icon — is read from this row at runtime instead, so a new
/// clinic, or a new kind of clinic, needs data rather than a release.
export class Clinic {
  constructor(
    readonly id: string,
    readonly name: string,
    readonly slug: string,
    /// The vertical, e.g. `dental`. A row in `clinic_types`, not a code enum:
    /// the platform can add a vertical without shipping a new build.
    readonly typeSlug: string,
    readonly typeName: string,
    readonly typeIconName: string | null = null,
    /// The structured chart the vertical keeps (`clinic_types.chart_kind`):
    /// `dental` for the odontogram, null for notes only.
    readonly chartKind: string | null = null,
    readonly timezone: string = 'Asia/Manila',
    /// Seeds the colour scheme, as `#RRGGBB`. Null means the platform default.
    readonly seedColor: string | null = null,
    /// A hosted URL, or `asset:<path>` for artwork bundled in this package.
    readonly logoUrl: string | null = null,
    readonly wordmarkUrl: string | null = null,
    /// What a patient types to join. Null when the clinic has switched
    /// self-service joins off. Only readable by people already at the clinic.
    readonly joinCode: string | null = null,
    readonly contactPhone: string | null = null,
    readonly address: string | null = null,
    readonly isActive: boolean = true,
    /// How long after a patient's last completed visit, with nothing booked,
    /// the patient list marks them due for recall.
    readonly recallMonths: number = 6,
  ) {}

  /// Expects the vertical embedded:
  ///
  ///   clinics?select=*,clinic_type:clinic_types(display_name,icon_name,
  ///                                             chart_kind)
  ///
  /// Without the embed the slug stands in for the display name, so a missing
  /// join degrades to "dental" rather than a crash.
  static fromJson(json: Json): Clinic {
    const type = json.clinic_type as Json | null | undefined;
    const typeSlug = json.type as string;
    return new Clinic(
      json.id,
      json.name,
      json.slug,
      typeSlug,
      type?.display_name ?? typeSlug,
      type?.icon_name ?? null,
      type?.chart_kind ?? null,
      json.timezone ?? 'Asia/Manila',
      parseHexColor(json.seed_color),
      json.logo_url ?? null,
      json.wordmark_url ?? null,
      json.join_code ?? null,
      json.contact_phone ?? null,
      json.address ?? null,
      json.is_active ?? true,
      json.recall_months == null ? 6 : Math.trunc(Number(json.recall_months)),
    );
  }

  get icon(): IconName {
    return clinicTypeIcon(this.typeIconName);
  }

  /// Whether this clinic charts teeth.
  get isDental(): boolean {
    return this.chartKind === 'dental';
  }
}

/// `#RRGGBB`, normalised to upper case. Anything else is null, so a malformed
/// value in the database falls back to the platform colour instead of
/// breaking the theme.
export function parseHexColor(hex: string | null | undefined): string | null {
  if (hex == null) return null;
  const m = /^#([0-9a-fA-F]{6})$/.exec(hex.trim());
  return m ? `#${m[1].toUpperCase()}` : null;
}

/// Maps `clinic_types.icon_name` to an icon.
///
/// Unknown names get a generic clinic icon rather than an error: the whole
/// point of verticals-as-data is that the database can know about one this
/// build has never heard of.
export function clinicTypeIcon(name: string | null | undefined): IconName {
  return (name != null && clinicTypeIcons[name]) || 'local-hospital';
}

const clinicTypeIcons: Record<string, IconName> = {
  medical_services: 'medical-services',
  remove_red_eye: 'remove-red-eye',
  visibility: 'visibility',
  child_care: 'child-care',
  face: 'face',
  pregnant_woman: 'pregnant-woman',
  psychology: 'psychology',
  healing: 'healing',
  monitor_heart: 'monitor-heart',
  hearing: 'hearing',
  spa: 'spa',
  vaccines: 'vaccines',
  local_hospital: 'local-hospital',
};
