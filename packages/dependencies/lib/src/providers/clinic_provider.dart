import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../models/clinic.dart';
import '../models/membership.dart';
import '../models/patient.dart';
import '../models/staff_invite.dart';
import 'supabase_providers.dart';

/// Which of the four apps is running.
///
/// Each app's `main.dart` overrides this, and it is the only thing a build
/// decides. WHICH clinic the app shows comes from the signed-in user at
/// runtime, so four builds serve every clinic on the platform.
final appRoleProvider = Provider<AppRole>(
  (ref) => throw UnimplementedError(
      'appRoleProvider must be overridden in the app\'s main.dart'),
);

/// The signed-in account's staff roles, one per clinic.
final myMembershipsProvider = FutureProvider<List<ClinicMembership>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyMemberships();
});

/// Every chart the signed-in account holds, one per clinic joined.
final myPatientsProvider = FutureProvider<List<Patient>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyPatients();
});

/// Every clinic RLS lets this user read — as staff anywhere or as a patient
/// anywhere. Broader than what any one app should offer; see
/// [myClinicsProvider].
final visibleClinicsProvider = FutureProvider<List<Clinic>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchClinics();
});

/// The clinics this user can use THIS app at.
///
/// An account can be a doctor at one clinic and a patient at another. The
/// doctor app must not offer the second, and the patient app must not offer
/// the first — so the clinics RLS returns are narrowed by the app's role: charts
/// for the patient app, a matching membership for the staff apps.
final myClinicsProvider = FutureProvider<List<Clinic>>((ref) async {
  final app = ref.watch(appRoleProvider);

  // Every dependency is watched before the first await, so a change to any of
  // them rebuilds this provider rather than being missed across the gap.
  final chartsFuture =
      app == AppRole.patient ? ref.watch(myPatientsProvider.future) : null;
  final membershipsFuture =
      app == AppRole.patient ? null : ref.watch(myMembershipsProvider.future);
  final clinicsFuture = ref.watch(visibleClinicsProvider.future);

  final Set<String> eligible;
  if (chartsFuture != null) {
    eligible = {for (final chart in await chartsFuture) chart.clinicId};
  } else {
    eligible = {
      for (final m in await membershipsFuture!)
        if (app.isGrantedBy(m.role)) m.clinicId,
    };
  }

  return [
    for (final clinic in await clinicsFuture)
      if (eligible.contains(clinic.id)) clinic,
  ];
});

/// The clinic the user picked, if they belong to several and have switched.
///
/// Null means "no explicit choice", which resolves to the first clinic. Reset
/// on every sign-in so one account's choice never carries into the next.
class SelectedClinicId extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(currentUserIdProvider);
    return null;
  }

  void select(String clinicId) => state = clinicId;
}

final selectedClinicIdProvider =
    NotifierProvider<SelectedClinicId, String?>(SelectedClinicId.new);

/// The clinic the app is currently showing.
///
/// Falls back to the first eligible clinic when nothing was picked, or when the
/// picked clinic is no longer one this user may use here (removed from staff,
/// clinic deactivated) — never to a clinic outside [myClinicsProvider].
final currentClinicProvider = Provider<AsyncValue<Clinic?>>((ref) {
  final selected = ref.watch(selectedClinicIdProvider);
  return ref.watch(myClinicsProvider).whenData((clinics) {
    for (final clinic in clinics) {
      if (clinic.id == selected) return clinic;
    }
    return clinics.isEmpty ? null : clinics.first;
  });
});

/// Every write needs the clinic's id; screens read it from here.
final currentClinicIdProvider = Provider<String?>(
  (ref) => ref.watch(currentClinicProvider).value?.id,
);

/// The signed-in account's staff membership at the current clinic, if any.
final currentMembershipProvider = Provider<ClinicMembership?>((ref) {
  final clinicId = ref.watch(currentClinicIdProvider);
  final memberships =
      ref.watch(myMembershipsProvider).value ?? const <ClinicMembership>[];
  for (final m in memberships) {
    if (m.clinicId == clinicId) return m;
  }
  return null;
});

/// Whether the signed-in account may manage the current clinic's admins —
/// false for a branch admin. Mirrors `private.is_full_admin`.
final isFullAdminProvider = Provider<bool>(
  (ref) => ref.watch(currentMembershipProvider)?.isFullAdmin ?? false,
);

/// Every staff code issued at the current clinic. Admin app only.
final staffInvitesProvider = FutureProvider<List<StaffInvite>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchStaffInvites(clinicId);
});

/// Requests at the current clinic still waiting for an admin.
final pendingStaffRequestsProvider = Provider<List<StaffInvite>>((ref) => [
      for (final invite
          in ref.watch(staffInvitesProvider).value ?? const <StaffInvite>[])
        if (invite.status == StaffInviteStatus.pending) invite,
    ]);

/// The signed-in account's own requests to join clinics as staff.
final myStaffRequestsProvider = FutureProvider<List<StaffRequest>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchMyStaffRequests();
});

/// Any clinic this user can see, by id — for labelling records (an
/// appointment's clinic) without refetching.
final clinicByIdProvider = Provider.family<Clinic?, String>((ref, id) {
  for (final clinic in ref.watch(visibleClinicsProvider).value ?? const []) {
    if (clinic.id == id) return clinic;
  }
  return null;
});
