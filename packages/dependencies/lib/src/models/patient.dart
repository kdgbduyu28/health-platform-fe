class Patient {
  const Patient({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    this.medicalNotes,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final String? medicalNotes;

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
