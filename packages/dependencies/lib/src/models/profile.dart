import 'app_role.dart';

/// A row from `public.profiles` — the 1:1 companion to the `auth.users` record
/// for the signed-in account.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    this.email,
    this.phone,
  });

  final String id;
  final AppRole role;
  final String fullName;
  final String? email;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        role: AppRole.fromWire(json['role'] as String),
        fullName: json['full_name'] as String,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return fullName.isEmpty ? '?' : fullName[0].toUpperCase();
  }

  /// The greeting name — "Juan" out of "Juan dela Cruz".
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;
}
