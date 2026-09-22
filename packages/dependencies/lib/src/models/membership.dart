import 'app_role.dart';

/// A row of `clinic_memberships`: the role one account holds at ONE clinic.
///
/// Roles are per clinic, not per account, so the same person can be an admin
/// at their own practice and a doctor at another. The name and email are only
/// present when the profile was embedded (the admin's staff list).
class ClinicMembership {
  const ClinicMembership({
    required this.profileId,
    required this.clinicId,
    required this.role,
    this.branchLocked = false,
    this.fullName,
    this.email,
  });

  final String profileId;
  final String clinicId;
  final AppRole role;

  /// A branch admin: an admin inside this clinic, but unable to manage its
  /// admins or to be an admin anywhere else. Only ever true for [AppRole.admin].
  final bool branchLocked;

  final String? fullName;
  final String? email;

  bool get isFullAdmin => role == AppRole.admin && !branchLocked;

  String get roleLabel => branchLocked ? 'Branch admin' : role.displayName;

  factory ClinicMembership.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return ClinicMembership(
      profileId: json['profile_id'] as String,
      clinicId: json['clinic_id'] as String,
      role: AppRole.fromWire(json['role'] as String),
      branchLocked: json['branch_locked'] as bool? ?? false,
      fullName: profile?['full_name'] as String?,
      email: profile?['email'] as String?,
    );
  }
}
