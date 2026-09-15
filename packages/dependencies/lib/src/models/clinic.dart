import 'package:flutter/material.dart';

/// A clinic tenant, as the signed-in user is allowed to see it.
///
/// Everything the apps used to compile in per flavor — name, colour, logo, the
/// vertical's icon — is read from this row at runtime instead, so a new clinic,
/// or a new kind of clinic, needs data rather than a release.
class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.slug,
    required this.typeSlug,
    required this.typeName,
    this.typeIconName,
    this.timezone = 'Asia/Manila',
    this.seedColor,
    this.logoUrl,
    this.wordmarkUrl,
    this.joinCode,
    this.contactPhone,
    this.address,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String slug;

  /// The vertical, e.g. `dental`. A row in `clinic_types`, not a Dart enum:
  /// the platform can add a vertical without shipping a new build.
  final String typeSlug;
  final String typeName;
  final String? typeIconName;

  final String timezone;

  /// Seeds the colour scheme. Null means the platform default.
  final Color? seedColor;

  /// A hosted URL, or `asset:<path>` for artwork bundled in this package.
  final String? logoUrl;
  final String? wordmarkUrl;

  /// What a patient types to join. Null when the clinic has switched
  /// self-service joins off. Only readable by people already at the clinic.
  final String? joinCode;

  final String? contactPhone;
  final String? address;
  final bool isActive;

  /// Expects the vertical embedded:
  ///
  ///   clinics?select=*,clinic_type:clinic_types(display_name,icon_name)
  ///
  /// Without the embed the slug stands in for the display name, so a missing
  /// join degrades to "dental" rather than a crash.
  factory Clinic.fromJson(Map<String, dynamic> json) {
    final type = json['clinic_type'] as Map<String, dynamic>?;
    final typeSlug = json['type'] as String;
    return Clinic(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      typeSlug: typeSlug,
      typeName: type?['display_name'] as String? ?? typeSlug,
      typeIconName: type?['icon_name'] as String?,
      timezone: json['timezone'] as String? ?? 'Asia/Manila',
      seedColor: parseHexColor(json['seed_color'] as String?),
      logoUrl: json['logo_url'] as String?,
      wordmarkUrl: json['wordmark_url'] as String?,
      joinCode: json['join_code'] as String?,
      contactPhone: json['contact_phone'] as String?,
      address: json['address'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  IconData get icon => clinicTypeIcon(typeIconName);
}

/// `#RRGGBB` → [Color]. Anything else is null, so a malformed value in the
/// database falls back to the platform colour instead of breaking the theme.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}

/// [Color] → `#RRGGBB`, the format `clinics.seed_color` is constrained to.
String toHexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// Maps `clinic_types.icon_name` to an icon.
///
/// Unknown names get a generic clinic icon rather than an error: the whole
/// point of verticals-as-data is that the database can know about one this
/// build has never heard of.
IconData clinicTypeIcon(String? name) =>
    _clinicTypeIcons[name] ?? Icons.local_hospital_outlined;

const _clinicTypeIcons = <String, IconData>{
  'medical_services': Icons.medical_services_outlined,
  'remove_red_eye': Icons.remove_red_eye_outlined,
  'visibility': Icons.visibility_outlined,
  'child_care': Icons.child_care_outlined,
  'face': Icons.face_outlined,
  'pregnant_woman': Icons.pregnant_woman_outlined,
  'psychology': Icons.psychology_outlined,
  'healing': Icons.healing_outlined,
  'monitor_heart': Icons.monitor_heart_outlined,
  'hearing': Icons.hearing_outlined,
  'spa': Icons.spa_outlined,
  'vaccines': Icons.vaccines_outlined,
  'local_hospital': Icons.local_hospital_outlined,
};
