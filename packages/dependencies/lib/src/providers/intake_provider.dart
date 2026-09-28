import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/patient_intake.dart';
import 'clinic_provider.dart';
import 'preferences_provider.dart';
import 'supabase_providers.dart';

/// The patient information form on one chart; null if never filled in.
final intakeProvider = FutureProvider.autoDispose
    .family<PatientIntake?, String>((ref, patientId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(healthRepositoryProvider).fetchIntake(patientId);
});

/// Whether the signed-in staff account has set its tablet PIN.
final hasStaffPinProvider = FutureProvider<bool>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(healthRepositoryProvider).hasStaffPin();
});

/// The front desk tablet, handed to a patient to fill in their own form.
///
/// While one is active the router shows nothing but the form at
/// `/:clinic/kiosk` — every other URL, the browser's back button and a
/// reload included, lands there — until a staff PIN ends it.
class KioskSession {
  const KioskSession({
    required this.slug,
    this.patientId,
    this.submitted = false,
  });

  /// The clinic the form is for.
  final String slug;

  /// The chart being filled in. Null for a new patient, until they submit.
  final String? patientId;

  /// The patient has sent the form and been asked to hand the tablet back.
  final bool submitted;

  String get path => '/$slug/kiosk';

  Map<String, dynamic> toJson() =>
      {'slug': slug, 'patient_id': patientId, 'submitted': submitted};

  static KioskSession? tryParse(String? json) {
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return KioskSession(
        slug: m['slug'] as String,
        patientId: m['patient_id'] as String?,
        submitted: m['submitted'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

class KioskNotifier extends Notifier<KioskSession?> {
  @override
  KioskSession? build() {
    // Signing out ends the hand-off: whoever signs in next starts clean.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (next == null) _write(null);
    });
    final app = ref.watch(appRoleProvider);
    if (!app.registersPatients) return null;
    final prefs = ref.read(preferencesProvider);
    // Opened signed out (the session expired): nothing to hand back.
    if (ref.read(currentUserIdProvider) == null) {
      prefs.setKioskSession(app, null);
      return null;
    }
    return KioskSession.tryParse(prefs.kioskSession(app));
  }

  void start({required String slug, String? patientId}) =>
      _write(KioskSession(slug: slug, patientId: patientId));

  /// The patient sent the form; [patientId] is their chart (new or not).
  void submitted(String patientId) {
    final s = state;
    if (s == null) return;
    _write(KioskSession(slug: s.slug, patientId: patientId, submitted: true));
  }

  /// Staff took the tablet back.
  void end() => _write(null);

  void _write(KioskSession? session) {
    state = session;
    final json = session == null ? null : jsonEncode(session.toJson());
    ref.read(preferencesProvider).setKioskSession(ref.read(appRoleProvider), json);
  }
}

final kioskProvider =
    NotifierProvider<KioskNotifier, KioskSession?>(KioskNotifier.new);
