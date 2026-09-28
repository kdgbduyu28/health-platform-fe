import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../theme/tone.dart';
import 'status_badge.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    this.showPatient = false,
    this.showDoctor = true,
  });

  final Appointment appointment;
  final VoidCallback onTap;
  final bool showPatient;
  final bool showDoctor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fmt = DateFormat('EEE, MMM d · h:mm a');
    if (showPatient) return _staff(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appointment.service,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  StatusBadge(status: appointment.status, small: true),
                ],
              ),
              const SizedBox(height: 8),
              _Row(
                icon: Icons.access_time_outlined,
                text: fmt.format(appointment.dateTime),
                color: cs.primary,
              ),
              if (showDoctor) ...[
                const SizedBox(height: 4),
                _Row(
                  icon: Icons.person_outline,
                  text: 'Dr. ${appointment.doctor.name}',
                  color: cs.onSurfaceVariant,
                ),
              ],
              if (showPatient) ...[
                const SizedBox(height: 4),
                _Row(
                  icon: Icons.account_circle_outlined,
                  text: appointment.patient.name,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on AppointmentCard {
  /// For the front desk and admins: who first, then what and with whom, the
  /// time in a block down the side — denser, so a tablet shows the morning
  /// at a glance. No date: the staff lists this serves are one day's.
  Widget _staff(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = appointment;
    final faded = a.status == AppointmentStatus.cancelled ||
        a.status == AppointmentStatus.noShow;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: a.status.color.readableIn(context).withAlpha(24),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(DateFormat('h:mm').format(a.dateTime),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                      DateFormat('a').format(a.dateTime),
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: faded ? TextDecoration.lineThrough : null,
                        color: faded ? cs.onSurfaceVariant : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        a.service,
                        if (showDoctor) 'Dr. ${a.doctor.name}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status: a.status, small: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}
