import { formatPeso } from './money';

type Json = Record<string, any>;

/// A bookable service from `public.services`.
///
/// The catalogue is per-clinic data an admin can edit, rather than a constant
/// compiled into the apps — two clinics of the same kind offer different
/// services.
export class Service {
  constructor(
    readonly id: string,
    readonly clinicId: string,
    readonly name: string,
    readonly durationMinutes: number,
    /// In the clinic's currency; null when the clinic has not set one.
    readonly price: number | null = null,
    readonly isActive: boolean = true,
  ) {}

  static fromJson(json: Json): Service {
    return new Service(
      json.id,
      json.clinic_id,
      json.name,
      json.duration_minutes,
      json.price == null ? null : Number(json.price),
      json.is_active ?? true,
    );
  }

  /// `₱1,500` — or null with no price set.
  get priceLabel(): string | null {
    return this.price == null ? null : formatPeso(this.price);
  }
}
