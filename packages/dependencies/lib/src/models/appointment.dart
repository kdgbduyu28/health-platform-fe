import 'appointment_status.dart';
import 'patient.dart';
import 'doctor.dart';

class Appointment {
  const Appointment({
    required this.id,
    required this.clinicId,
    required this.patient,
    required this.doctor,
    required this.dateTime,
    required this.service,
    required this.status,
    this.notes,
    this.serviceId,
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
  final String? notes;
  final String? serviceId;

  /// Expects the chart (with its person) and the doctor embedded:
  ///
  ///   appointments?select=*,patient:patients(*,person:persons(*)),
  ///                        doctor:doctors(*)
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
      notes: json['notes'] as String?,
      serviceId: json['service_id'] as String?,
    );
  }

  Appointment copyWith({AppointmentStatus? status, String? notes}) {
    return Appointment(
      id: id,
      clinicId: clinicId,
      patient: patient,
      doctor: doctor,
      dateTime: dateTime,
      service: service,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      serviceId: serviceId,
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
