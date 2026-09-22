/// A day or days nobody can book: one doctor's leave, or — with no
/// [doctorId] — the whole clinic closed. From `public.doctor_time_off`.
class TimeOff {
  const TimeOff({
    required this.id,
    required this.clinicId,
    required this.startsOn,
    required this.endsOn,
    this.doctorId,
    this.reason,
  });

  final String id;
  final String clinicId;
  final String? doctorId;

  /// Calendar days in the clinic's time zone, both inclusive.
  final DateTime startsOn;
  final DateTime endsOn;
  final String? reason;

  bool get isClosure => doctorId == null;

  factory TimeOff.fromJson(Map<String, dynamic> json) => TimeOff(
        id: json['id'] as String,
        clinicId: json['clinic_id'] as String,
        doctorId: json['doctor_id'] as String?,
        startsOn: DateTime.parse(json['starts_on'] as String),
        endsOn: DateTime.parse(json['ends_on'] as String),
        reason: json['reason'] as String?,
      );
}
