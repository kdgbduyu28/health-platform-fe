import 'package:flutter/material.dart';

import 'app_role.dart';

/// One entry in an account's inbox, from `public.notifications`.
///
/// The database writes these as visits and bills move (see
/// 20260924120200_notifications in health-platform-be) and pushes them to
/// subscribed browsers. Each belongs to one app: a doctor who is also a
/// patient somewhere sees each in the right place.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.app,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.clinicId,
    this.link,
    this.appointmentId,
    this.readAt,
  });

  final String id;
  final AppRole app;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? clinicId;

  /// A path in this app, clinic slug included: `/dtouchdental/appointments/…`.
  final String? link;
  final String? appointmentId;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  IconData get icon => switch (kind) {
        'booking_requested' => Icons.event_note_outlined,
        'visit_confirmed' => Icons.check_circle_outline,
        'visit_moved' => Icons.update,
        'visit_cancelled' => Icons.event_busy_outlined,
        'visit_reminder' => Icons.alarm,
        'patient_arrived' => Icons.chair_outlined,
        'patient_note' => Icons.chat_bubble_outline,
        'invoice_issued' => Icons.receipt_long_outlined,
        _ => Icons.notifications_none,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        app: AppRole.fromWire(json['app'] as String),
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        clinicId: json['clinic_id'] as String?,
        link: json['link'] as String?,
        appointmentId: json['appointment_id'] as String?,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );
}
