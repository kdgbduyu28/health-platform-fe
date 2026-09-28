import 'package:flutter/foundation.dart';
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

/// Charts at the current clinic matching what was typed — the first few, for
/// a picker. Searched in the database, so the clinic's whole patient list is
/// never downloaded to find one person.
///
/// Waits a moment before asking, so typing a name sends one request rather
/// than one per letter: a keystroke replaces this provider before the wait is
/// over.
final patientSearchProvider = FutureProvider.autoDispose
    .family<List<Patient>, String>((ref, query) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  final repo = ref.watch(healthRepositoryProvider);
  if (clinicId == null) return const [];
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!ref.mounted) return const [];
  final page = await repo.searchPatients(clinicId,
      query: query.trim().isEmpty ? null : query, limit: 8);
  return [for (final l in page.patients) l.patient];
});

/// How many charts the current clinic holds.
final patientCountProvider = FutureProvider<int>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return 0;
  final page =
      await ref.watch(healthRepositoryProvider).searchPatients(clinicId, limit: 1);
  return page.total;
});

/// What the patient list is showing: the search, the remark filters, the
/// sort, and which page.
@immutable
class PatientTableQuery {
  const PatientTableQuery({
    this.search = '',
    this.filters = const {},
    this.sort = PatientSort.name,
    this.descending = false,
    this.page = 0,
    this.pageSize = 25,
  });

  final String search;
  final Set<PatientFlag> filters;
  final PatientSort sort;
  final bool descending;

  /// Zero-based.
  final int page;
  final int pageSize;

  PatientTableQuery copyWith({
    String? search,
    Set<PatientFlag>? filters,
    PatientSort? sort,
    bool? descending,
    int? page,
    int? pageSize,
  }) =>
      PatientTableQuery(
        search: search ?? this.search,
        filters: filters ?? this.filters,
        sort: sort ?? this.sort,
        descending: descending ?? this.descending,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
      );

  @override
  bool operator ==(Object other) =>
      other is PatientTableQuery &&
      other.search == search &&
      setEquals(other.filters, filters) &&
      other.sort == sort &&
      other.descending == descending &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(search,
      Object.hashAllUnordered(filters), sort, descending, page, pageSize);
}

/// One page of the patient list. Searching waits a moment, like
/// [patientSearchProvider], so typing a name sends one request.
final patientTableProvider = FutureProvider.autoDispose
    .family<PatientPage, PatientTableQuery>((ref, q) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  final repo = ref.watch(healthRepositoryProvider);
  if (clinicId == null) return const PatientPage(patients: [], total: 0);
  final search = q.search.trim();
  if (search.isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!ref.mounted) return const PatientPage(patients: [], total: 0);
  }
  return repo.searchPatients(
    clinicId,
    query: search.isEmpty ? null : search,
    offset: q.page * q.pageSize,
    limit: q.pageSize,
    filters: q.filters,
    sort: q.sort,
    descending: q.descending,
  );
});

/// After registering a patient, every list of them is stale.
void invalidatePatientLists(WidgetRef ref) {
  ref
    ..invalidate(patientSearchProvider)
    ..invalidate(patientCountProvider)
    ..invalidate(patientTableProvider);
}

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

/// What a booking screen may offer: see `public.available_slots`. When
/// moving a visit, [ignore] is that visit, so it does not block itself.
typedef SlotQuery = ({
  String doctorId,
  DateTime day,
  String? serviceId,
  String? ignore,
});

final availableSlotsProvider =
    FutureProvider.autoDispose.family<List<DateTime>, SlotQuery>(
  (ref, q) => ref.watch(healthRepositoryProvider).fetchAvailableSlots(
        doctorId: q.doctorId,
        day: DateTime(q.day.year, q.day.month, q.day.day),
        serviceId: q.serviceId,
        ignoreAppointmentId: q.ignore,
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
