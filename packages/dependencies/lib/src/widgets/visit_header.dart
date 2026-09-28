import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import 'status_badge.dart';

/// The top of a staff visit page: status, service, when, and who.
///
/// The status sits on a pill of the page's own surface, which its colours
/// are chosen to read on, rather than on the clinic-colour gradient. [who]
/// (the patient and doctor) is shown on staff pages, where "who is this" is
/// the first question; a patient's own page leaves it out.
class VisitHeader extends StatelessWidget {
  const VisitHeader({super.key, required this.appointment, this.who});

  final Appointment appointment;
  final String? who;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = appointment;
    final on = cs.onPrimary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: StatusBadge(status: a.status),
          ),
          const SizedBox(height: 12),
          Text(
            a.service,
            style: theme.textTheme.headlineSmall
                ?.copyWith(color: on, fontWeight: FontWeight.bold),
          ),
          if (who != null) ...[
            const SizedBox(height: 2),
            Text(
              who!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: on, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            [
              DateFormat('EEE, MMM d · h:mm a').format(a.dateTime),
              '${a.durationMinutes} min',
            ].join('  ·  '),
            style: TextStyle(color: on.withAlpha(210), fontSize: 13),
          ),
          if (a.rescheduledFrom case final from?)
            Text(
              'Moved from ${DateFormat('EEE, MMM d · h:mm a').format(from)}',
              style: TextStyle(color: on.withAlpha(180), fontSize: 12),
            ),
        ],
      ),
    );
  }
}
