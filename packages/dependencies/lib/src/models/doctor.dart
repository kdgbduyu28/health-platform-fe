/// `available_weekdays` (1=Mon … 7=Sun) as people write it: `Mon–Fri`,
/// `Mon, Wed, Fri`, `Every day`. A run of three or more days is a range.
String formatWeekdays(Iterable<int> weekdays) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final days = weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
  if (days.length == 7) return 'Every day';

  final parts = <String>[];
  var i = 0;
  while (i < days.length) {
    var j = i;
    while (j + 1 < days.length && days[j + 1] == days[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${names[days[i] - 1]}–${names[days[j] - 1]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add(names[days[k] - 1]);
      }
    }
    i = j + 1;
  }
  return parts.join(', ');
}

/// A roster row from `public.doctors`. One per clinic a doctor practises at:
/// the same account may appear on several clinics' rosters.
class Doctor {
  const Doctor({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.specialty,
    required this.availableWeekdays,
    required this.availableTimeSlots,
    this.profileId,
  });

  final String id;
  final String clinicId;
  final String name;
  final String specialty;
  final List<int> availableWeekdays; // 1=Monday … 7=Sunday
  final List<String> availableTimeSlots; // '09:00', '09:30', …
  final String? profileId;

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] as String,
      clinicId: json['clinic_id'] as String,
      name: json['full_name'] as String,
      specialty: json['specialty'] as String? ?? '',
      availableWeekdays: (json['available_weekdays'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      availableTimeSlots:
          (json['available_time_slots'] as List<dynamic>? ?? [])
              .map((e) => e as String)
              .toList(),
      profileId: json['profile_id'] as String?,
    );
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }
}
