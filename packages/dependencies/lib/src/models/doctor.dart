import 'clinic_type.dart';

class Doctor {
  const Doctor({
    required this.id,
    required this.name,
    required this.specialty,
    required this.clinicType,
    required this.availableWeekdays,
    required this.availableTimeSlots,
  });

  final String id;
  final String name;
  final String specialty;
  final ClinicType clinicType;
  final List<int> availableWeekdays; // 1=Monday … 7=Sunday
  final List<String> availableTimeSlots; // '09:00', '09:30', …

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name[0].toUpperCase();
  }
}
