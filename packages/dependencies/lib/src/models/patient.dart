class Patient {
  const Patient({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    this.medicalNotes,
    this.profileId,
    this.registeredClinicId,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final String? medicalNotes;

  /// The `auth.users` account this chart belongs to, if any. Walk-ins
  /// registered by an assistant have no account, so this stays null.
  final String? profileId;

  /// The clinic holding this chart. Drives who on staff can read the record.
  final String? registeredClinicId;

  /// `patients.email` is nullable in Postgres but the UI treats it as a plain
  /// string, so an absent address becomes empty rather than null.
  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        name: json['full_name'] as String,
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        dateOfBirth: json['date_of_birth'] == null
            ? null
            : DateTime.parse(json['date_of_birth'] as String),
        medicalNotes: json['medical_notes'] as String?,
        profileId: json['profile_id'] as String?,
        registeredClinicId: json['registered_clinic_id'] as String?,
      );

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name[0].toUpperCase();
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
