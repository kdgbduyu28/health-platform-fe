import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../models/appointment.dart';
import '../models/clinical_note.dart';
import '../models/patient.dart';
import 'appointments_provider.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// The signed-in account's staff role at the clinic being shown.
///
/// Null in the patient app — even for an account that is also staff at this
/// clinic, since the patient app must never show clinic-side content — and for
/// anyone with no membership here.
final currentClinicRoleProvider = FutureProvider<AppRole?>((ref) async {
  if (ref.watch(appRoleProvider) == AppRole.patient) return null;
  final clinicId = ref.watch(currentClinicIdProvider);
  final memberships = await ref.watch(myMembershipsProvider.future);
  for (final m in memberships) {
    if (m.clinicId == clinicId) return m.role;
  }
  return null;
});

/// Whether this user may see clinical notes at the current clinic.
///
/// The database enforces this on its own (20260915120000). The screens still
/// need to know, because for anyone else a notes query returns nothing — and
/// "Nothing on file" is not something to show a receptionist about a patient
/// who has a latex allergy recorded.
final canSeeClinicalNotesProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(currentClinicRoleProvider.future);
  return role?.seesClinicalNotes ?? false;
});

/// One chart, with its person.
final patientByIdProvider =
    FutureProvider.autoDispose.family<Patient?, String>((ref, patientId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchPatient(patientId);
});

/// Every appointment on one chart, newest first, carrying consultation notes
/// when the user may see them.
///
/// Refetches whenever the shared appointment list changes, so a booking or a
/// status change made elsewhere in the app shows up here too.
final patientHistoryProvider = FutureProvider.autoDispose
    .family<List<Appointment>, String>((ref, patientId) async {
  ref.watch(appointmentsProvider.select((list) => list.value));
  final repo = ref.watch(healthRepositoryProvider);
  final withNotes = await ref.watch(canSeeClinicalNotesProvider.future);
  return repo.fetchPatientHistory(patientId, withVisitNotes: withNotes);
});

/// The standing medical note on a chart. Null when there is none, and always
/// null — without a request — for users who may not see it.
final chartNoteProvider = FutureProvider.autoDispose
    .family<ClinicalNote?, String>((ref, patientId) async {
  final repo = ref.watch(healthRepositoryProvider);
  if (!await ref.watch(canSeeClinicalNotesProvider.future)) return null;
  return repo.fetchChartNote(patientId);
});

/// The consultation note on one appointment. Same rules as [chartNoteProvider].
final visitNoteProvider = FutureProvider.autoDispose
    .family<ClinicalNote?, String>((ref, appointmentId) async {
  final repo = ref.watch(healthRepositoryProvider);
  if (!await ref.watch(canSeeClinicalNotesProvider.future)) return null;
  return repo.fetchVisitNote(appointmentId);
});
