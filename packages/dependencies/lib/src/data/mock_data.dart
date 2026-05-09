import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/clinic_type.dart';
import '../models/doctor.dart';
import '../models/patient.dart';

class MockData {
  static const _morning = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  ];
  static const _afternoon = [
    '13:00', '13:30', '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
  ];
  static const _allDay = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '13:00', '13:30', '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
  ];

  // ── Doctors ──────────────────────────────────────────────────────────────

  static final List<Doctor> doctors = [
    // Dental
    Doctor(
      id: 'd1',
      name: 'Maria Santos',
      specialty: 'General Dentistry',
      clinicType: ClinicType.dental,
      availableWeekdays: [1, 2, 3, 4, 5],
      availableTimeSlots: _morning,
    ),
    Doctor(
      id: 'd2',
      name: 'Jose Reyes',
      specialty: 'Orthodontics',
      clinicType: ClinicType.dental,
      availableWeekdays: [1, 3, 5],
      availableTimeSlots: _afternoon,
    ),
    Doctor(
      id: 'd3',
      name: 'Ana Cruz',
      specialty: 'Oral Surgery',
      clinicType: ClinicType.dental,
      availableWeekdays: [2, 4, 6],
      availableTimeSlots: _morning,
    ),
    // Optometry
    Doctor(
      id: 'o1',
      name: 'Carlos Bautista',
      specialty: 'Clinical Optometry',
      clinicType: ClinicType.optometry,
      availableWeekdays: [1, 2, 3, 4, 5],
      availableTimeSlots: _morning,
    ),
    Doctor(
      id: 'o2',
      name: 'Grace Flores',
      specialty: 'Pediatric Optometry',
      clinicType: ClinicType.optometry,
      availableWeekdays: [2, 4],
      availableTimeSlots: _afternoon,
    ),
    Doctor(
      id: 'o3',
      name: 'Ramon Dela Cruz',
      specialty: 'Low Vision Specialist',
      clinicType: ClinicType.optometry,
      availableWeekdays: [1, 3, 5],
      availableTimeSlots: _allDay,
    ),
    // Pediatrics
    Doctor(
      id: 'p1',
      name: 'Elena Garcia',
      specialty: 'General Pediatrics',
      clinicType: ClinicType.pedia,
      availableWeekdays: [1, 2, 3, 4, 5, 6],
      availableTimeSlots: _morning,
    ),
    Doctor(
      id: 'p2',
      name: 'Miguel Torres',
      specialty: 'Neonatology',
      clinicType: ClinicType.pedia,
      availableWeekdays: [1, 2, 3, 4, 5],
      availableTimeSlots: _afternoon,
    ),
    Doctor(
      id: 'p3',
      name: 'Liza Mendoza',
      specialty: 'Developmental Pediatrics',
      clinicType: ClinicType.pedia,
      availableWeekdays: [3, 5],
      availableTimeSlots: _allDay,
    ),
  ];

  // ── Patients ─────────────────────────────────────────────────────────────

  static final List<Patient> patients = [
    Patient(
      id: 'pt1',
      name: 'Juan dela Cruz',
      phone: '09171234567',
      email: 'juan@email.com',
      dateOfBirth: DateTime(1990, 3, 15),
    ),
    Patient(
      id: 'pt2',
      name: 'Maria Reyes',
      phone: '09281234567',
      email: 'maria@email.com',
      dateOfBirth: DateTime(1985, 7, 22),
    ),
    Patient(
      id: 'pt3',
      name: 'Pedro Santos',
      phone: '09391234567',
      email: 'pedro@email.com',
      dateOfBirth: DateTime(2015, 1, 10),
    ),
    Patient(
      id: 'pt4',
      name: 'Ana Bautista',
      phone: '09451234567',
      email: 'ana@email.com',
      dateOfBirth: DateTime(2010, 8, 5),
    ),
    Patient(
      id: 'pt5',
      name: 'Carlos Flores',
      phone: '09561234567',
      email: 'carlos@email.com',
      dateOfBirth: DateTime(1975, 11, 30),
    ),
    Patient(
      id: 'pt6',
      name: 'Lisa Torres',
      phone: '09671234567',
      email: 'lisa@email.com',
      dateOfBirth: DateTime(2020, 4, 18),
    ),
  ];

  // ── Appointments (today = 2026-05-09) ───────────────────────────────────

  static final List<Appointment> appointments = [
    // ─ DENTAL ─
    Appointment(
      id: 'a1',
      patient: patients[0], // Juan
      doctor: doctors[0],   // Dr. Santos
      dateTime: DateTime(2026, 5, 9, 9, 0),
      service: 'Teeth Cleaning',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a2',
      patient: patients[1], // Maria
      doctor: doctors[0],
      dateTime: DateTime(2026, 5, 9, 10, 0),
      service: 'Dental Filling',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a3',
      patient: patients[4], // Carlos
      doctor: doctors[1],   // Dr. Reyes
      dateTime: DateTime(2026, 5, 9, 14, 0),
      service: 'Braces Adjustment',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a4',
      patient: patients[0], // Juan – future
      doctor: doctors[0],
      dateTime: DateTime(2026, 5, 14, 9, 0),
      service: 'Root Canal',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a5',
      patient: patients[2],
      doctor: doctors[2],   // Dr. Cruz
      dateTime: DateTime(2026, 5, 16, 10, 30),
      service: 'Tooth Extraction',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a6',
      patient: patients[0], // Juan – past
      doctor: doctors[0],
      dateTime: DateTime(2026, 5, 2, 9, 0),
      service: 'Teeth Cleaning',
      status: AppointmentStatus.completed,
      notes: 'Good oral hygiene. Follow-up in 6 months.',
      clinicType: ClinicType.dental,
    ),
    Appointment(
      id: 'a7',
      patient: patients[1],
      doctor: doctors[0],
      dateTime: DateTime(2026, 4, 28, 10, 0),
      service: 'Dental X-Ray',
      status: AppointmentStatus.completed,
      notes: 'No cavities detected.',
      clinicType: ClinicType.dental,
    ),

    // ─ OPTOMETRY ─
    Appointment(
      id: 'b1',
      patient: patients[1],
      doctor: doctors[3],   // Dr. Bautista
      dateTime: DateTime(2026, 5, 9, 9, 30),
      service: 'Eye Examination',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.optometry,
    ),
    Appointment(
      id: 'b2',
      patient: patients[3], // Ana
      doctor: doctors[4],   // Dr. Flores
      dateTime: DateTime(2026, 5, 9, 14, 0),
      service: 'Pediatric Eye Exam',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.optometry,
    ),
    Appointment(
      id: 'b3',
      patient: patients[0], // Juan – future
      doctor: doctors[3],
      dateTime: DateTime(2026, 5, 13, 10, 0),
      service: 'Contact Lens Fitting',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.optometry,
    ),
    Appointment(
      id: 'b4',
      patient: patients[4],
      doctor: doctors[5],   // Dr. Dela Cruz
      dateTime: DateTime(2026, 5, 15, 11, 0),
      service: 'Glaucoma Screening',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.optometry,
    ),
    Appointment(
      id: 'b5',
      patient: patients[0], // Juan – past
      doctor: doctors[3],
      dateTime: DateTime(2026, 5, 2, 9, 0),
      service: 'Eye Examination',
      status: AppointmentStatus.completed,
      notes: 'Prescribed -2.50 OD, -2.75 OS. Recommend glasses.',
      clinicType: ClinicType.optometry,
    ),

    // ─ PEDIA ─
    Appointment(
      id: 'c1',
      patient: patients[2], // Pedro
      doctor: doctors[6],   // Dr. Garcia
      dateTime: DateTime(2026, 5, 9, 8, 0),
      service: 'Well-Child Visit',
      status: AppointmentStatus.completed,
      clinicType: ClinicType.pedia,
    ),
    Appointment(
      id: 'c2',
      patient: patients[5], // Lisa
      doctor: doctors[6],
      dateTime: DateTime(2026, 5, 9, 10, 30),
      service: 'Vaccination',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.pedia,
    ),
    Appointment(
      id: 'c3',
      patient: patients[3], // Ana
      doctor: doctors[7],   // Dr. Torres
      dateTime: DateTime(2026, 5, 9, 15, 0),
      service: 'Sick Visit',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.pedia,
    ),
    Appointment(
      id: 'c4',
      patient: patients[0], // Juan (as parent) – future
      doctor: doctors[6],
      dateTime: DateTime(2026, 5, 16, 9, 0),
      service: 'Growth Assessment',
      status: AppointmentStatus.pending,
      clinicType: ClinicType.pedia,
    ),
    Appointment(
      id: 'c5',
      patient: patients[5],
      doctor: doctors[8],   // Dr. Mendoza
      dateTime: DateTime(2026, 5, 21, 14, 0),
      service: 'Development Screening',
      status: AppointmentStatus.confirmed,
      clinicType: ClinicType.pedia,
    ),
    Appointment(
      id: 'c6',
      patient: patients[2],
      doctor: doctors[6],
      dateTime: DateTime(2026, 4, 25, 9, 0),
      service: 'Vaccination',
      status: AppointmentStatus.completed,
      notes: 'MMR vaccine administered. Next dose in 12 months.',
      clinicType: ClinicType.pedia,
    ),
  ];
}
