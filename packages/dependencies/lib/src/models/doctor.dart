import 'clinic_type.dart';

class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    required this.specialty,
    required this.clinicType,
    required this.availableWeekdays,
    required this.availableTimeSlots,
    this.clinicId,
    this.profileId,
  });

  final String id;
  final String name;
  final String specialty;
  final ClinicType clinicType;
  final List<int> availableWeekdays; // 1=Monday … 7=Sunday
  final List<String> availableTimeSlots; // '09:00', '09:30', …
  final String? clinicId;
  final String? profileId;

  /// Expects the clinic to be embedded, e.g.
  /// `doctors?select=*,clinic:clinics(type)`, since [clinicType] cannot be
  /// derived from the doctors row alone.
  factory Doctor.fromJson(Map<String, dynamic> json) {
    final clinic = json['clinic'] as Map<String, dynamic>?;
    return Doctor(
      id: json['id'] as String,
      name: json['full_name'] as String,
      specialty: json['specialty'] as String? ?? '',
      clinicType: ClinicType.fromWire(clinic!['type'] as String),
      availableWeekdays: (json['available_weekdays'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      availableTimeSlots:
          (json['available_time_slots'] as List<dynamic>? ?? [])
              .map((e) => e as String)
              .toList(),
      clinicId: json['clinic_id'] as String?,
      profileId: json['profile_id'] as String?,
    );
  }

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name[0].toUpperCase();
  }
}
