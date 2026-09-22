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

/// A doctor's working day as an admin thinks of it — first start time, last
/// start time, every N minutes — rather than the list of start times
/// (`available_time_slots`) the database keeps. Minutes since midnight.
typedef WorkingHours = ({int first, int last, int step});

/// `08:00` … `11:30` every 30 → the start times, as `HH:MM`.
List<String> generateTimeSlots(WorkingHours hours) {
  if (hours.step <= 0 || hours.last < hours.first) return const [];
  return [
    for (var m = hours.first; m <= hours.last && m < 24 * 60; m += hours.step)
      formatClock(m),
  ];
}

/// The pattern behind [slots], if they are one evenly spaced run; null for
/// anything irregular (lunch breaks, hand-edited lists).
WorkingHours? workingHoursOf(List<String> slots) {
  final minutes = [for (final s in slots) parseClock(s)];
  if (minutes.isEmpty || minutes.contains(null)) return null;
  final sorted = [for (final m in minutes) m!]..sort();
  if (sorted.length == 1) return (first: sorted.first, last: sorted.first, step: 30);
  final step = sorted[1] - sorted[0];
  for (var i = 2; i < sorted.length; i++) {
    if (sorted[i] - sorted[i - 1] != step) return null;
  }
  return step <= 0 ? null : (first: sorted.first, last: sorted.last, step: step);
}

/// `08:00–11:30, every 30 min` — or `9 set times` when irregular.
String describeTimeSlots(List<String> slots) {
  if (slots.isEmpty) return 'No times set';
  final hours = workingHoursOf(slots);
  if (hours == null) return '${slots.length} set times';
  if (hours.first == hours.last) return 'At ${formatClock(hours.first)}';
  return '${formatClock(hours.first)}–${formatClock(hours.last)}, '
      'every ${hours.step} min';
}

/// `HH:MM` → minutes since midnight, or null if malformed.
int? parseClock(String value) {
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// Minutes since midnight → `HH:MM`, the format the database checks.
String formatClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

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
    this.isActive = true,
  });

  final String id;
  final String clinicId;
  final String name;
  final String specialty;
  final List<int> availableWeekdays; // 1=Monday … 7=Sunday
  final List<String> availableTimeSlots; // '09:00', '09:30', …
  final String? profileId;
  final bool isActive;

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
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }
}
