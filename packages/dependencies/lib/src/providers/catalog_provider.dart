import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_repository.dart';
import '../models/clinic.dart';
import '../models/doctor.dart';
import '../models/patient.dart';
import '../models/service.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// All three clinics. Small and effectively static, so it is fetched once and
/// reused rather than re-queried per screen.
final clinicsProvider = FutureProvider<List<Clinic>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchClinics();
});

/// The clinic row for this build flavor. Every write needs its `id`, which is
/// why the apps cannot work from [ClinicType] alone.
final currentClinicProvider = Provider<AsyncValue<Clinic?>>((ref) {
  final type = ref.watch(clinicTypeProvider);
  return ref.watch(clinicsProvider).whenData((list) => list.byType(type));
});

final currentClinicIdProvider = Provider<String?>(
  (ref) => ref.watch(currentClinicProvider).value?.id,
);

/// Active doctors at this clinic. Empty until the clinic id resolves.
final doctorsProvider = FutureProvider<List<Doctor>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchDoctors(clinicId);
});

/// The bookable service catalogue for this clinic, replacing the old
/// hardcoded `ClinicType.services` list.
final servicesProvider = FutureProvider<List<Service>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchServices(clinicId);
});

/// Patients the signed-in user may see. For a patient that is just their own
/// chart; for staff it is their clinic's roster plus anyone referred in. The
/// filtering is done by RLS, not here.
final patientsProvider = FutureProvider<List<Patient>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchPatients();
});

/// The signed-in user's own patient chart, if their account has been linked to
/// one. Null for staff, and for a patient who signed up but was never linked.
final myPatientProvider = FutureProvider<Patient?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyPatient();
});

/// The roster row for a signed-in doctor. Replaces the old
/// `currentDoctorProvider`, which just grabbed the first doctor of the clinic
/// type regardless of who was using the app.
final currentDoctorProvider = FutureProvider<Doctor?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyDoctor();
});
