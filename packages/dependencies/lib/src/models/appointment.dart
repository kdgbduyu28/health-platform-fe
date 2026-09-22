import 'appointment_status.dart';
import 'clinical_note.dart';
import 'doctor.dart';
import 'patient.dart';

class Appointment {
  const Appointment({
    required this.id,
    required this.clinicId,
    required this.patient,
    required this.doctor,
    required this.dateTime,
    required this.service,
    required this.status,
    this.patientNote,
    this.visitNote,
    this.serviceId,
    this.durationMinutes = 30,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String clinicId;

  /// The chart at [clinicId]. The database refuses an appointment whose chart
  /// belongs to any other clinic.
  final Patient patient;
  final Doctor doctor;
  final DateTime dateTime;
  final String service;
  final AppointmentStatus status;

  /// What the doctor wants the patient to read. Visible to anyone who can see
  /// the appointment; only the clinic's doctors and admins can write it.
  final String? patientNote;

  /// The consultation note — present only when the appointment was fetched
  /// with it embedded (a clinician's view of a patient's history). Null
  /// otherwise, which does not mean no note was written.
  final ClinicalNote? visitNote;
  final String? serviceId;

  /// From the service, set by the database. The visit runs until [endsAt].
  final int durationMinutes;

  /// When the front desk checked the patient in, the doctor started, and the
  /// doctor finished. Stamped by the database as the status moves.
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  DateTime get endsAt => dateTime.add(Duration(minutes: durationMinutes));

  /// Expects the chart (with its person) and the doctor embedded:
  ///
  ///   appointments?select=*,patient:patients(*,person:persons(*)),
  ///                        doctor:doctors(*)
  ///
  /// optionally with `visit_note:visit_notes(*)` as well.
  ///
  /// `scheduled_at` comes back as a timestamptz in UTC; it is converted to the
  /// device's local zone so the UI formats it as the clinic's wall clock.
  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      clinicId: json['clinic_id'] as String,
      patient: Patient.fromJson(json['patient'] as Map<String, dynamic>),
      doctor: Doctor.fromJson(json['doctor'] as Map<String, dynamic>),
      dateTime: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      service: json['service_name'] as String,
      status: AppointmentStatus.fromWire(json['status'] as String),
      patientNote: _blankToNull(json['patient_note'] as String?),
      visitNote: ClinicalNote.fromNullableJson(json['visit_note']),
      serviceId: json['service_id'] as String?,
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      arrivedAt: _time(json['arrived_at']),
      startedAt: _time(json['started_at']),
      completedAt: _time(json['completed_at']),
    );
  }

  Appointment copyWith({AppointmentStatus? status, String? patientNote}) {
    return Appointment(
      id: id,
      clinicId: clinicId,
      patient: patient,
      doctor: doctor,
      dateTime: dateTime,
      service: service,
      status: status ?? this.status,
      patientNote: patientNote ?? this.patientNote,
      visitNote: visitNote,
      serviceId: serviceId,
      durationMinutes: durationMinutes,
      arrivedAt: arrivedAt,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  bool get isUpcoming => dateTime.isAfter(DateTime.now());

  bool get isToday {
    final now = DateTime.now();
    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
