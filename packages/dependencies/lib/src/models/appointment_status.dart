import 'package:flutter/material.dart';

/// Mirrors `public.appointment_status`. The flow, which the database enforces
/// (see 20260923120100 in health-platform-be):
///
///   pending → confirmed → arrived → inConsultation → completed
///                 └───────────────────────┘ (a doctor may start from confirmed)
///
/// plus [cancelled] before the consultation and [noShow] once a confirmed
/// visit's time has passed.
enum AppointmentStatus {
  pending('pending'),
  confirmed('confirmed'),
  arrived('arrived'),
  inConsultation('in_consultation'),
  completed('completed'),
  cancelled('cancelled'),
  noShow('no_show');

  const AppointmentStatus(this.wire);

  final String wire;

  static AppointmentStatus fromWire(String value) =>
      values.firstWhere((s) => s.wire == value);

  /// Still on the doctor's calendar: it blocks the time and counts as a
  /// visit to come or in progress. Cancelled visits and no-shows free it.
  bool get holdsTime => this != cancelled && this != noShow;

  /// Not yet finished one way or another.
  bool get isOpen =>
      this == pending ||
      this == confirmed ||
      this == arrived ||
      this == inConsultation;

  /// What a patient may still cancel from the app. Later than this they
  /// call the clinic; the database refuses it too.
  bool get patientCanCancel => this == pending || this == confirmed;

  /// What the front desk may still cancel.
  bool get staffCanCancel => this == pending || this == confirmed || this == arrived;

  /// In the building: checked in, or with the doctor.
  bool get isOnSite => this == arrived || this == inConsultation;

  String get displayName => switch (this) {
        pending => 'Pending',
        confirmed => 'Confirmed',
        arrived => 'Waiting',
        inConsultation => 'With doctor',
        completed => 'Completed',
        cancelled => 'Cancelled',
        noShow => 'No-show',
      };

  Color get color => switch (this) {
        pending => const Color(0xFFFF9800),
        confirmed => const Color(0xFF4CAF50),
        arrived => const Color(0xFF9C27B0),
        inConsultation => const Color(0xFF00897B),
        completed => const Color(0xFF2196F3),
        cancelled => const Color(0xFFF44336),
        noShow => const Color(0xFF757575),
      };

  IconData get icon => switch (this) {
        pending => Icons.schedule,
        confirmed => Icons.check_circle_outline,
        arrived => Icons.chair_outlined,
        inConsultation => Icons.medical_services_outlined,
        completed => Icons.task_alt,
        cancelled => Icons.cancel_outlined,
        noShow => Icons.person_off_outlined,
      };
}
