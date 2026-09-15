/// A patient chart: one person's record at ONE clinic.
///
/// The database keeps identity and clinical content apart. `persons` holds who
/// someone is (name, phone, date of birth) and is shared by every clinic that
/// treats them; `patients` holds the chart (clinical notes) and belongs to a
/// single clinic, which is what stops one clinic reading another's notes.
///
/// The screens want one object per patient, so the person is embedded and
/// flattened here:
///
///   patients?select=*,person:persons(*)
class Patient {
  const Patient({
    required this.id,
    required this.personId,
    required this.clinicId,
    required this.name,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    this.medicalNotes,
  });

  /// The chart id — what appointments point at.
  final String id;
  final String personId;
  final String clinicId;

  final String name;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;

  /// Clinic-private. Never follows the person to another clinic.
  final String? medicalNotes;

  /// Nullable person columns become empty strings, because the UI treats them
  /// as plain text; a missing embed degrades the same way rather than crashing.
  factory Patient.fromJson(Map<String, dynamic> json) {
    final person =
        json['person'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    return Patient(
      id: json['id'] as String,
      personId: json['person_id'] as String,
      clinicId: json['clinic_id'] as String,
      name: person['full_name'] as String? ?? '',
      phone: person['phone'] as String? ?? '',
      email: person['email'] as String? ?? '',
      dateOfBirth: person['date_of_birth'] == null
          ? null
          : DateTime.parse(person['date_of_birth'] as String),
      medicalNotes: json['medical_notes'] as String?,
    );
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int a = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      a--;
    }
    return a;
  }
}
