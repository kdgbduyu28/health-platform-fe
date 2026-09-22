import 'app_role.dart';

/// Where a staff code is in its life. Mirrors `staff_invites.status`.
///
///   open ──redeem──▶ pending ──approve──▶ approved
///     │                 │  └───reject───▶ rejected
///     └────revoke───────┴──────────────▶ revoked
enum StaffInviteStatus {
  open,
  pending,
  approved,
  rejected,
  revoked;

  static StaffInviteStatus fromWire(String value) =>
      StaffInviteStatus.values.byName(value);
}

/// A single-use code an admin issued for one doctor or assistant, and the
/// request it became once someone entered it. Admin app only; RLS returns
/// these to the clinic's admins and nobody else.
class StaffInvite {
  const StaffInvite({
    required this.id,
    required this.clinicId,
    required this.role,
    required this.code,
    required this.status,
    required this.expiresAt,
    this.label,
    this.redeemerName,
    this.redeemerEmail,
    this.redeemedAt,
  });

  final String id;
  final String clinicId;
  final AppRole role;
  final String code;
  final StaffInviteStatus status;
  final DateTime expiresAt;

  /// Who the admin issued it for, e.g. "Dr Reyes".
  final String? label;

  /// Copied from the applicant's account when they entered the code.
  final String? redeemerName;
  final String? redeemerEmail;
  final DateTime? redeemedAt;

  factory StaffInvite.fromJson(Map<String, dynamic> json) => StaffInvite(
        id: json['id'] as String,
        clinicId: json['clinic_id'] as String,
        role: AppRole.fromWire(json['role'] as String),
        code: json['code'] as String,
        status: StaffInviteStatus.fromWire(json['status'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
        label: json['label'] as String?,
        redeemerName: json['redeemer_name'] as String?,
        redeemerEmail: json['redeemer_email'] as String?,
        redeemedAt: _parseTime(json['redeemed_at']),
      );

  /// An open code past its expiry. The database leaves its status alone and
  /// simply refuses to redeem it.
  bool isExpired([DateTime? now]) =>
      status == StaffInviteStatus.open &&
      !expiresAt.isAfter(now ?? DateTime.now());

  /// Who is asking, as the admin should see it.
  String get applicant => redeemerName ?? redeemerEmail ?? 'Someone';
}

/// The applicant's own view of a request: which clinic, and where it stands.
/// They are not a member yet, so this is all they can see of the clinic.
class StaffRequest {
  const StaffRequest({
    required this.id,
    required this.clinicName,
    required this.role,
    required this.status,
    this.redeemedAt,
  });

  final String id;
  final String clinicName;
  final AppRole role;
  final StaffInviteStatus status;
  final DateTime? redeemedAt;

  factory StaffRequest.fromJson(Map<String, dynamic> json) => StaffRequest(
        id: json['id'] as String,
        clinicName: json['clinic_name'] as String,
        role: AppRole.fromWire(json['role'] as String),
        status: StaffInviteStatus.fromWire(json['status'] as String),
        redeemedAt: _parseTime(json['redeemed_at']),
      );
}

DateTime? _parseTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
