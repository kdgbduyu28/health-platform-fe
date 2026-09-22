import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

/// Renders an [AsyncValue] with consistent loading and error states.
///
/// Every screen used to read a synchronous list from `MockData`, so none of
/// them had anywhere to show "still loading" or "that failed". Routing them
/// all through this keeps those two states from being quietly dropped — an
/// RLS denial or a paused free-tier project surfaces as a visible, retryable
/// error rather than an empty list that looks like "no appointments".
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(error: err, onRetry: onRetry),
    );
  }
}

/// Sliver-emitting variant, for the screens built out of [CustomScrollView].
class SliverAsyncView<T> extends StatelessWidget {
  const SliverAsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: value.when(
        data: builder,
        loading: () => const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => _ErrorView(error: err, onRetry: onRetry),
      ),
    );
  }
}

/// Loading/error guard for screens whose body does not wrap neatly in an
/// [AsyncView] — detail screens that build one big `ListView` from a single
/// record, mostly.
///
/// Returns a ready-to-return scaffold while [value] is loading or has failed,
/// and null once data is available, so the caller continues at its normal
/// indentation:
///
///   final guard = asyncGuard(appointmentAsync, appBar: AppBar(...));
///   if (guard != null) return guard;
///
/// A refresh that already has data does not trip the guard — the screen keeps
/// showing the previous record instead of flashing a spinner.
Widget? asyncGuard(
  AsyncValue<Object?> value, {
  PreferredSizeWidget? appBar,
  VoidCallback? onRetry,
}) {
  if (value.hasValue) return null;
  if (value.hasError) {
    return Scaffold(
      appBar: appBar,
      body: _ErrorView(error: value.error!, onRetry: onRetry),
    );
  }
  return Scaffold(
    appBar: appBar,
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text(
            'Could not load data',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            describeError(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Turns Supabase's exception types into something a clinic receptionist could
/// act on, instead of a raw stack trace.
String describeError(Object error) {
  // The database functions (join_clinic, invite_staff, book_walk_in, …) raise
  // messages written for the person using the app: "that clinic code is not
  // valid", "a clinic must keep at least one admin". Plain RAISE EXCEPTION
  // arrives as SQLSTATE P0001 — show its message, not the exception wrapper.
  if (error is PostgrestException && error.code == 'P0001') {
    return error.message;
  }
  // Supabase Auth's messages are already sentences ("Invalid login
  // credentials"); the exception's toString wraps them in a status code.
  if (error is AuthException) {
    if (error.message.contains('expired or is invalid')) {
      return 'That code is wrong or has expired. Request a new one.';
    }
    return error.message;
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup')) {
    return 'No connection. Check your network and try again.';
  }
  // The partial unique index on (doctor_id, scheduled_at) is what makes
  // concurrent bookings safe, so losing that race is an ordinary outcome for a
  // patient — not an error to dump raw.
  if (text.contains('appointments_no_double_booking') ||
      text.contains('duplicate key')) {
    return 'That time slot has just been taken. Please pick another.';
  }
  if (text.contains('row-level security')) {
    return 'You do not have permission to do that.';
  }
  if (text.contains('JWT') || text.contains('token is expired')) {
    return 'Your session has expired. Please sign in again.';
  }
  return text.replaceFirst('Exception: ', '');
}
