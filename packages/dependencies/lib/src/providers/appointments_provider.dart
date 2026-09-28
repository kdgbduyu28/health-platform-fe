import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import 'catalog_provider.dart';
import 'clinic_provider.dart';
import 'supabase_providers.dart';

/// Where the working set of appointments begins: a week before today, so the
/// schedule can look back a few days and "last visit" is at hand. Everything
/// older is read on demand — see [pastAppointmentsProvider].
final appointmentWindowStartProvider = Provider<DateTime>((ref) {
  ref.watch(currentUserIdProvider);
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - 7);
});

/// Every appointment the signed-in user is allowed to see from
/// [appointmentWindowStartProvider] on.
///
/// There is no role filtering here on purpose — RLS decides the rows. A
/// patient gets their own bookings at every clinic they have joined, staff get
/// the bookings of every clinic they work at, and a signed-out caller gets
/// nothing. The derived providers below narrow that to the current clinic.
class AppointmentsNotifier extends AsyncNotifier<List<Appointment>> {
  @override
  Future<List<Appointment>> build() {
    // Refetch when the session changes, so signing out cannot leave the
    // previous user's appointments on screen.
    ref.watch(currentUserIdProvider);
    return ref.watch(healthRepositoryProvider).fetchAppointments(
        since: ref.watch(appointmentWindowStartProvider));
  }

  Future<void> refresh() async {
    // Visits read one by one or a page at a time are views of the same rows.
    ref
      ..invalidate(appointmentFetchProvider)
      ..invalidate(pastAppointmentsProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(healthRepositoryProvider).fetchAppointments(
          since: ref.read(appointmentWindowStartProvider)),
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

  /// Enters a visit that happened but was never logged: for [patientId] on
  /// file, or for someone new ([newPatientName], [newPatientPhone]) whose
  /// chart is registered with it. With [complete] (doctors and admins) it is
  /// marked completed; otherwise it stays confirmed for one of them to close.
  Future<void> recordMissedVisit({
    required String clinicId,
    String? patientId,
    String? newPatientName,
    String? newPatientPhone,
    required String doctorId,
    required String serviceName,
    required DateTime scheduledAt,
    String? serviceId,
    required bool complete,
  }) async {
    final repo = ref.read(healthRepositoryProvider);
    try {
      final id = patientId != null
          ? await repo.recordPastVisit(
              clinicId: clinicId,
              patientId: patientId,
              doctorId: doctorId,
              serviceName: serviceName,
              scheduledAt: scheduledAt,
              serviceId: serviceId,
            )
          : await repo.bookWalkIn(
              clinicId: clinicId,
              fullName: newPatientName!,
              phone: newPatientPhone!,
              doctorId: doctorId,
              serviceName: serviceName,
              scheduledAt: scheduledAt,
              serviceId: serviceId,
            );
      if (complete) await repo.completeRecordedVisit(id);
    } finally {
      // Even a half-done record (booked, not completed) is now on file.
      await refresh();
    }
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

  /// Moves a visit; see [HealthRepository.reschedule].
  Future<void> reschedule(String id, DateTime to, {String? doctorId}) async {
    await ref.read(healthRepositoryProvider).reschedule(id, to, doctorId: doctorId);
    await refresh();
  }

  /// The note the patient reads. Blank clears it. The database refuses this
  /// from anyone but the clinic's doctors and admins.
  Future<void> updatePatientNote(String id, String? note) async {
    await ref.read(healthRepositoryProvider).updatePatientNote(id, note);
    await refresh();
  }
}

final appointmentsProvider =
    AsyncNotifierProvider<AppointmentsNotifier, List<Appointment>>(
  AppointmentsNotifier.new,
);

/// Appointments at the clinic the app is currently showing.
final clinicAppointmentsProvider =
    Provider<AsyncValue<List<Appointment>>>((ref) {
  final clinicId = ref.watch(currentClinicIdProvider);
  return ref.watch(appointmentsProvider).whenData(
        (list) => list.where((a) => a.clinicId == clinicId).toList(),
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
              a.status.holdsTime)
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
              a.status.holdsTime)
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

/// One appointment by id: from the loaded window when it is there, else
/// fetched on its own — a visit opened from a patient's history may be years
/// old.
final appointmentByIdProvider =
    Provider.family<AsyncValue<Appointment?>, String>((ref, id) {
  final loaded = ref.watch(appointmentsProvider);
  if (!loaded.hasValue) return loaded.whenData((_) => null);
  for (final a in loaded.requireValue) {
    if (a.id == id) return AsyncValue.data(a);
  }
  return ref.watch(appointmentFetchProvider(id));
});

/// One appointment straight from the database.
final appointmentFetchProvider = FutureProvider.autoDispose
    .family<Appointment?, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchAppointment(id);
});

// ── Older visits, a page at a time ──────────────────────────────────────────

/// Whose older visits: one doctor's, one chart's, or (both null) the whole
/// current clinic's.
typedef PastAppointmentsQuery = ({String? doctorId, String? patientId});

/// Visits before the loaded window, newest first, as far back as has been
/// asked for.
class PastAppointments {
  const PastAppointments({
    this.items = const [],
    this.hasMore = true,
    this.loadingMore = false,
    this.error,
  });

  final List<Appointment> items;
  final bool hasMore;
  final bool loadingMore;

  /// Why the last "load more" failed; the pages already shown stay.
  final Object? error;

  PastAppointments copyWith({
    List<Appointment>? items,
    bool? hasMore,
    bool? loadingMore,
    Object? error,
  }) =>
      PastAppointments(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
      );
}

class PastAppointmentsNotifier extends AsyncNotifier<PastAppointments> {
  PastAppointmentsNotifier(this.query);

  final PastAppointmentsQuery query;

  static const pageSize = 20;

  Future<List<Appointment>> _page(int offset) async {
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) return const [];
    return ref.read(healthRepositoryProvider).fetchPastAppointments(
          clinicId: clinicId,
          before: ref.read(appointmentWindowStartProvider),
          doctorId: query.doctorId,
          patientId: query.patientId,
          offset: offset,
          limit: pageSize,
        );
  }

  @override
  Future<PastAppointments> build() async {
    ref
      ..watch(currentClinicIdProvider)
      ..watch(appointmentWindowStartProvider);
    final first = await _page(0);
    return PastAppointments(items: first, hasMore: first.length == pageSize);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncValue.data(current.copyWith(loadingMore: true));
    try {
      final next = await _page(current.items.length);
      state = AsyncValue.data(current.copyWith(
        items: [...current.items, ...next],
        hasMore: next.length == pageSize,
        loadingMore: false,
      ));
    } catch (e) {
      state = AsyncValue.data(current.copyWith(loadingMore: false, error: e));
    }
  }
}

final pastAppointmentsProvider = AsyncNotifierProvider.autoDispose
    .family<PastAppointmentsNotifier, PastAppointments, PastAppointmentsQuery>(
  PastAppointmentsNotifier.new,
);
