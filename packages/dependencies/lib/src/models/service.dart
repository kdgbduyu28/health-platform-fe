/// A bookable service from `public.services`.
///
/// This replaces the hardcoded `ClinicType.services` list: the catalogue is now
/// per-clinic data an admin can edit, rather than a constant compiled into the
/// apps.
class Service {
  const Service({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.durationMinutes,
  });

  final String id;
  final String clinicId;
  final String name;
  final int durationMinutes;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        clinicId: json['clinic_id'] as String,
        name: json['name'] as String,
        durationMinutes: json['duration_minutes'] as int,
      );
}
