import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/appointment.dart';
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
