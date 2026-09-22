import 'money.dart';

/// A bookable service from `public.services`.
///
/// The catalogue is per-clinic data an admin can edit, rather than a constant
/// compiled into the apps — two clinics of the same kind offer different
/// services.
class Service {
  const Service({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.durationMinutes,
    this.price,
    this.isActive = true,
  });

  final String id;
  final String clinicId;
  final String name;
  final int durationMinutes;

  /// In the clinic's currency; null when the clinic has not set one.
  final double? price;
  final bool isActive;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        clinicId: json['clinic_id'] as String,
        name: json['name'] as String,
        durationMinutes: json['duration_minutes'] as int,
        price: (json['price'] as num?)?.toDouble(),
        isActive: json['is_active'] as bool? ?? true,
      );

  /// `₱1,500` — or null with no price set.
  String? get priceLabel {
    final p = price;
    return p == null ? null : formatPeso(p);
  }
}
