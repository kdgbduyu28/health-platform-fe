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
  });

  final String id;
  final Patient patient;
  final Doctor doctor;
  final DateTime dateTime;
  final String service;
  final AppointmentStatus status;
  final String? notes;
  final ClinicType clinicType;

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
