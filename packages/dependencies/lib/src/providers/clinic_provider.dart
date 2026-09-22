import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../models/clinic.dart';
import '../models/clinic_page.dart';
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
  // Signed out, RLS would return nothing anyway; skip the round trips. The
  // router asks this on every navigation, landing page included.
  if (ref.watch(currentUserIdProvider) == null) return const [];

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

/// The clinic slug in the URL — `dtouchdental` in `/dtouchdental/book` — or
/// null outside any clinic (`/`, `/not-found`).
///
/// The URL is the only record of which clinic is open: that is what makes a
/// clinic bookmarkable and survive a reload. `ClinicScope` copies the route's
/// slug in here; nothing else should write it.
class RouteClinicSlug extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? slug) {
    if (state != slug) state = slug;
  }
}

final routeClinicSlugProvider =
    NotifierProvider<RouteClinicSlug, String?>(RouteClinicSlug.new);

/// The public page of the clinic at a slug; null when no active clinic has it.
/// Readable signed out.
final clinicPageProvider = FutureProvider.family<ClinicPage?, String>(
  (ref, slug) => ref.watch(healthRepositoryProvider).fetchClinicPage(slug),
);

/// The clinic in the URL, if this user may use this app there.
///
/// Null at a clinic they do not belong to (the router shows them the join or
/// staff-code screen instead), and never a clinic outside [myClinicsProvider].
final currentClinicProvider = Provider<AsyncValue<Clinic?>>((ref) {
  final slug = ref.watch(routeClinicSlugProvider);
  return ref.watch(myClinicsProvider).whenData((clinics) {
    for (final clinic in clinics) {
      if (clinic.slug == slug) return clinic;
    }
    return null;
  });
});

/// The clinic to brand the screen with: the user's own row when they belong
/// to the clinic in the URL, otherwise its public page — so the sign-in, join
/// and landing screens wear the clinic's colours too. Null outside a clinic.
final routeBrandClinicProvider = Provider<Clinic?>((ref) {
  final slug = ref.watch(routeClinicSlugProvider);
  if (slug == null) return null;
  return ref.watch(currentClinicProvider).value ??
      ref.watch(clinicPageProvider(slug)).value?.clinic;
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
