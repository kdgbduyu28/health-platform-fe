import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../providers/appointments_provider.dart';
import 'async_view.dart';

/// Moves [appointment] to [to] and says how it went.
///
/// The database decides which moves are allowed (and who may make them), so
/// a refusal is expected, not exceptional: its message is shown as-is — it
/// is written for the person at the screen ("A completed visit cannot
/// become confirmed."). Returns whether the change was saved.
Future<bool> changeAppointmentStatus(
  BuildContext context,
  WidgetRef ref,
  Appointment appointment,
  AppointmentStatus to, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(appointmentsProvider.notifier).updateStatus(appointment.id, to);
    if (done != null) {
      messenger?.showSnackBar(SnackBar(
        content: Text(done),
        behavior: SnackBarBehavior.floating,
      ));
    }
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
      content: Text(describeError(e)),
      behavior: SnackBarBehavior.floating,
    ));
    return false;
  }
}

/// Asks before cancelling — it cannot be undone from the app — then cancels.
Future<bool> confirmAndCancelAppointment(
  BuildContext context,
  WidgetRef ref,
  Appointment appointment, {
  String? who,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel appointment?'),
      content: Text(who == null
          ? 'This frees the time for someone else.'
          : 'Cancel $who\'s appointment? This frees the time for someone else.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Cancel it'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  return changeAppointmentStatus(
    context,
    ref,
    appointment,
    AppointmentStatus.cancelled,
    done: 'Appointment cancelled',
  );
}
