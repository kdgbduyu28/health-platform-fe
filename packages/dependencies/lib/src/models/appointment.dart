import 'clinic_type.dart';
import 'appointment_status.dart';
import 'patient.dart';
import 'doctor.dart';

class Appointment {
  const Appointment({
    required this.id,
    required this.patient,
    required this.doctor,
    required this.dateTime,
    required this.service,
    required this.status,
    this.notes,
    required this.clinicType,
    this.clinicId,
    this.serviceId,
  });

  final String id;
  final Patient patient;
  final Doctor doctor;
  final DateTime dateTime;
  final String service;
  final AppointmentStatus status;
  final String? notes;
  final ClinicType clinicType;
  final String? clinicId;
  final String? serviceId;

  /// Expects patient, doctor and clinic to be embedded:
  ///
  ///   appointments?select=*,clinic:clinics(type),patient:patients(*),
  ///                        doctor:doctors(*,clinic:clinics(type))
  ///
  /// `scheduled_at` comes back as a timestamptz in UTC; it is converted to the
  /// device's local zone so the UI formats it as the clinic's wall clock.
  factory Appointment.fromJson(Map<String, dynamic> json) {
    final clinic = json['clinic'] as Map<String, dynamic>?;
    return Appointment(
      id: json['id'] as String,
      patient: Patient.fromJson(json['patient'] as Map<String, dynamic>),
      doctor: Doctor.fromJson(json['doctor'] as Map<String, dynamic>),
      dateTime: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      service: json['service_name'] as String,
      status: AppointmentStatus.fromWire(json['status'] as String),
      notes: json['notes'] as String?,
      clinicType: ClinicType.fromWire(clinic!['type'] as String),
      clinicId: json['clinic_id'] as String?,
      serviceId: json['service_id'] as String?,
    );
  }

  Appointment copyWith({AppointmentStatus? status, String? notes}) {
    return Appointment(
      id: id,
      patient: patient,
      doctor: doctor,
      dateTime: dateTime,
      service: service,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      clinicType: clinicType,
      clinicId: clinicId,
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
