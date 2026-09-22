import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/doctor.dart';
import '../models/membership.dart';
import '../models/patient.dart';
import '../models/service.dart';
import '../models/time_off.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// Active doctors at the current clinic. Empty until the clinic resolves.
final doctorsProvider = FutureProvider<List<Doctor>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchDoctors(clinicId);
});

/// The bookable service catalogue at the current clinic.
final servicesProvider = FutureProvider<List<Service>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchServices(clinicId);
});

/// The charts held at the current clinic — the staff apps' patient list.
final patientsProvider = FutureProvider<List<Patient>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchPatients(clinicId);
});

/// The signed-in patient's chart at the current clinic. Null for staff.
final myPatientProvider = Provider<AsyncValue<Patient?>>((ref) {
  final clinicId = ref.watch(currentClinicIdProvider);
  return ref.watch(myPatientsProvider).whenData((charts) {
    for (final chart in charts) {
      if (chart.clinicId == clinicId) return chart;
    }
    return null;
  });
});

/// Roster rows linked to the signed-in account, across every clinic.
final myDoctorsProvider = FutureProvider<List<Doctor>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyDoctors();
});

/// The signed-in doctor's roster row at the current clinic.
final currentDoctorProvider = Provider<AsyncValue<Doctor?>>((ref) {
  final clinicId = ref.watch(currentClinicIdProvider);
  return ref.watch(myDoctorsProvider).whenData((rows) {
    for (final row in rows) {
      if (row.clinicId == clinicId) return row;
    }
    return null;
  });
});

/// Everyone on staff at the current clinic. Admin app only.
final staffProvider = FutureProvider<List<ClinicMembership>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchStaff(clinicId);
});

/// The whole roster at the current clinic, inactive doctors included. Admin.
final rosterProvider = FutureProvider<List<Doctor>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchRoster(clinicId);
});

/// The whole catalogue at the current clinic, retired services included.
final catalogueProvider = FutureProvider<List<Service>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchCatalogue(clinicId);
});

/// Leave and closures at the current clinic that have not ended yet.
final timeOffProvider = FutureProvider<List<TimeOff>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchTimeOff(clinicId);
});

/// What a booking screen may offer: see `public.available_slots`.
typedef SlotQuery = ({String doctorId, DateTime day, String? serviceId});

final availableSlotsProvider =
    FutureProvider.autoDispose.family<List<DateTime>, SlotQuery>(
  (ref, q) => ref.watch(healthRepositoryProvider).fetchAvailableSlots(
        doctorId: q.doctorId,
        day: DateTime(q.day.year, q.day.month, q.day.day),
        serviceId: q.serviceId,
      ),
);

/// After an admin changes the roster, catalogue or time off, every view of
/// them — booking screens included — must refetch.
void invalidateCatalog(WidgetRef ref) {
  ref.invalidate(doctorsProvider);
  ref.invalidate(servicesProvider);
  ref.invalidate(rosterProvider);
  ref.invalidate(catalogueProvider);
  ref.invalidate(timeOffProvider);
  ref.invalidate(availableSlotsProvider);
}
