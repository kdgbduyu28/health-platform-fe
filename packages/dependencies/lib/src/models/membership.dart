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
    this.fullName,
    this.email,
  });

  final String profileId;
  final String clinicId;
  final AppRole role;
  final String? fullName;
  final String? email;

  factory ClinicMembership.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return ClinicMembership(
      profileId: json['profile_id'] as String,
      clinicId: json['clinic_id'] as String,
      role: AppRole.fromWire(json['role'] as String),
      fullName: profile?['full_name'] as String?,
      email: profile?['email'] as String?,
    );
  }
}
