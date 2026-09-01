import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import 'catalog_provider.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// Every appointment the signed-in user is allowed to see.
///
/// There is no role filtering here on purpose — RLS decides the rows. A
/// patient gets their own bookings across all three clinics, a doctor gets
/// their clinic's, an assistant the same, and a signed-out caller gets
/// nothing. The derived providers below only narrow that down for the UI.
class AppointmentsNotifier extends AsyncNotifier<List<Appointment>> {
  @override
  Future<List<Appointment>> build() {
    // Refetch when the session changes, so signing out cannot leave the
    // previous user's appointments on screen.
    ref.watch(currentUserIdProvider);
    return ref.watch(healthRepositoryProvider).fetchAppointments();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(healthRepositoryProvider).fetchAppointments(),
    );
  }

  Future<void> book({
    required String clinicId,
    required String patientId,
    required String doctorId,
    required String serviceName,
    required DateTime scheduledAt,
    String? serviceId,
    AppointmentStatus status = AppointmentStatus.pending,
  }) async {
    await ref.read(healthRepositoryProvider).book(
          clinicId: clinicId,
          patientId: patientId,
          doctorId: doctorId,
          serviceName: serviceName,
          scheduledAt: scheduledAt,
          serviceId: serviceId,
          status: status,
        );
    await refresh();
  }

  /// Registers a walk-in and books them in one transaction. Returns the new
  /// appointment id.
  Future<String> bookWalkIn({
    required String clinicId,
    required String fullName,
    required String phone,
    required String doctorId,
    required String serviceName,
    required DateTime scheduledAt,
    String? serviceId,
    String? email,
  }) async {
    final id = await ref.read(healthRepositoryProvider).bookWalkIn(
          clinicId: clinicId,
          fullName: fullName,
          phone: phone,
          doctorId: doctorId,
          serviceName: serviceName,
          scheduledAt: scheduledAt,
          serviceId: serviceId,
          email: email,
        );
    await refresh();
    return id;
  }

  Future<void> updateStatus(String id, AppointmentStatus status) async {
    await ref.read(healthRepositoryProvider).updateStatus(id, status);
    await refresh();
  }

  Future<void> updateNotes(String id, String notes) async {
    await ref.read(healthRepositoryProvider).updateNotes(id, notes);
    await refresh();
  }
}

final appointmentsProvider =
    AsyncNotifierProvider<AppointmentsNotifier, List<Appointment>>(
  AppointmentsNotifier.new,
);

/// Appointments belonging to this build's clinic.
final clinicAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final type = ref.watch(clinicTypeProvider);
  return ref.watch(appointmentsProvider).whenData(
        (list) => list.where((a) => a.clinicType == type).toList(),
      );
});

final todayAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  return ref.watch(clinicAppointmentsProvider).whenData(
        (list) => [...list.where((a) => a.isToday)]
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
      );
});

final upcomingAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final now = DateTime.now();
  return ref.watch(clinicAppointmentsProvider).whenData(
        (list) => [
          ...list.where((a) =>
              a.dateTime.isAfter(now) &&
              a.status != AppointmentStatus.cancelled)
        ]..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
      );
});

// ── Patient-scoped views ────────────────────────────────────────────────────
// RLS already limits a signed-in patient to their own rows; filtering by
// patient id as well keeps these correct if a staff account ever opens the
// patient app.

final myAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final mine = ref.watch(myPatientProvider).value;
  return ref.watch(clinicAppointmentsProvider).whenData((list) {
    final rows = mine == null
        ? [...list]
        : [...list.where((a) => a.patient.id == mine.id)];
    return rows..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  });
});

final myUpcomingAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final now = DateTime.now();
  return ref.watch(myAppointmentsProvider).whenData(
        (list) => [
          ...list.where((a) =>
              a.dateTime.isAfter(now) &&
              a.status != AppointmentStatus.cancelled)
        ]..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
      );
});

// ── Doctor-scoped views ─────────────────────────────────────────────────────

final myDoctorAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final me = ref.watch(currentDoctorProvider).value;
  return ref.watch(clinicAppointmentsProvider).whenData((list) {
    final rows = me == null
        ? [...list]
        : [...list.where((a) => a.doctor.id == me.id)];
    return rows..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  });
});

final myDoctorTodayProvider = Provider<AsyncValue<List<Appointment>>>((ref) {
  return ref
      .watch(myDoctorAppointmentsProvider)
      .whenData((list) => list.where((a) => a.isToday).toList());
});

/// Look up one appointment by id out of whatever is already loaded.
final appointmentByIdProvider =
    Provider.family<AsyncValue<Appointment?>, String>((ref, id) {
  return ref.watch(appointmentsProvider).whenData((list) {
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  });
});
