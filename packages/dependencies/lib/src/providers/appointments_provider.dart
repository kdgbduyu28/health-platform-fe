import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_data.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import 'clinic_provider.dart';

class AppointmentsNotifier extends Notifier<List<Appointment>> {
  @override
  List<Appointment> build() => List.from(MockData.appointments);

  void add(Appointment appointment) => state = [...state, appointment];

  void updateStatus(String id, AppointmentStatus status) {
    state = [for (final a in state) if (a.id == id) a.copyWith(status: status) else a];
  }

  void updateNotes(String id, String notes) {
    state = [for (final a in state) if (a.id == id) a.copyWith(notes: notes) else a];
  }
}

final appointmentsProvider =
    NotifierProvider<AppointmentsNotifier, List<Appointment>>(AppointmentsNotifier.new);

final clinicAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final type = ref.watch(clinicTypeProvider);
  return ref.watch(appointmentsProvider).where((a) => a.clinicType == type).toList();
});

final todayAppointmentsProvider = Provider<List<Appointment>>((ref) {
  return ref
      .watch(clinicAppointmentsProvider)
      .where((a) => a.isToday)
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
});

final upcomingAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(clinicAppointmentsProvider)
      .where((a) => a.dateTime.isAfter(now) && a.status != AppointmentStatus.cancelled)
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
});

// Patient-scoped views (patient_app uses pt1 – Juan dela Cruz as the current user)
final currentPatientIdProvider = Provider<String>((ref) => 'pt1');

final myAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final pid = ref.watch(currentPatientIdProvider);
  return ref
      .watch(clinicAppointmentsProvider)
      .where((a) => a.patient.id == pid)
      .toList()
    ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
});

final myUpcomingAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final now = DateTime.now();
  return ref
      .watch(myAppointmentsProvider)
      .where((a) => a.dateTime.isAfter(now) && a.status != AppointmentStatus.cancelled)
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
});

// Doctor-scoped views – doctor_app uses the first doctor of the active clinic type
final currentDoctorProvider = Provider((ref) {
  final type = ref.watch(clinicTypeProvider);
  return MockData.doctors.firstWhere((d) => d.clinicType == type);
});

final myDoctorAppointmentsProvider = Provider<List<Appointment>>((ref) {
  final doc = ref.watch(currentDoctorProvider);
  return ref
      .watch(clinicAppointmentsProvider)
      .where((a) => a.doctor.id == doc.id)
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
});

final myDoctorTodayProvider = Provider<List<Appointment>>((ref) {
  return ref.watch(myDoctorAppointmentsProvider).where((a) => a.isToday).toList();
});
