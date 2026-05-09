import 'package:flutter/material.dart';

enum AppointmentStatus {
  pending,
  confirmed,
  completed,
  cancelled;

  String get displayName => switch (this) {
        AppointmentStatus.pending => 'Pending',
        AppointmentStatus.confirmed => 'Confirmed',
        AppointmentStatus.completed => 'Completed',
        AppointmentStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        AppointmentStatus.pending => const Color(0xFFFF9800),
        AppointmentStatus.confirmed => const Color(0xFF4CAF50),
        AppointmentStatus.completed => const Color(0xFF2196F3),
        AppointmentStatus.cancelled => const Color(0xFFF44336),
      };

  IconData get icon => switch (this) {
        AppointmentStatus.pending => Icons.schedule,
        AppointmentStatus.confirmed => Icons.check_circle_outline,
        AppointmentStatus.completed => Icons.task_alt,
        AppointmentStatus.cancelled => Icons.cancel_outlined,
      };
}
