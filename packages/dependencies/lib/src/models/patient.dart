/// A patient chart: one person's record at ONE clinic.
///
/// The database keeps identity and clinical content apart. `persons` holds who
/// someone is (name, phone, date of birth) and is shared by every clinic that
/// treats them; `patients` is the chart, and belongs to a single clinic. The
/// clinical text on a chart lives in `chart_notes`, readable only by that
/// clinic's doctors and admins — see [ClinicalNote].
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
  });

  /// The chart id — what appointments point at.
  final String id;
  final String personId;
  final String clinicId;

  final String name;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;

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

  /// Whether this patient is what someone typed into a search box: part of
  /// the name, or part of the phone number however it is formatted.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    final digits = _localDigits(q);
    return digits.isNotEmpty && _localDigits(phone).contains(digits);
  }

  /// Same phone number, however either was typed. How the front desk spots
  /// that a "new" walk-in is already on file.
  bool hasPhone(String other) {
    final mine = _localDigits(phone);
    return mine.length >= 7 && mine == _localDigits(other);
  }
}

/// Digits only, with a Philippine +63 prefix rewritten to the local 0, so
/// "+63 917 123 4567" and "0917-123-4567" compare equal.
String _localDigits(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.startsWith('63') && d.length == 12 ? '0${d.substring(2)}' : d;
}
