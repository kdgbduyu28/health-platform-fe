import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/adaptive_layout.dart';
import '../models/appointment.dart';
import '../providers/appointments_provider.dart';
import 'async_view.dart';
import 'patient_directory_screen.dart';

/// A "Past" tab: the recent visits already loaded, then older ones fetched a
/// page at a time as the list scrolls down.
///
/// [recent] are visits inside the loaded window, newest first; the older
/// pages ([pastAppointmentsProvider]) start where the window ends, so the two
/// never overlap.
class PastAppointmentsList extends ConsumerWidget {
  const PastAppointmentsList({
    super.key,
    required this.recent,
    required this.query,
    required this.itemBuilder,
    required this.emptyMessage,
    this.emptySubtitle,
    this.padding = const EdgeInsets.all(16),
  });

  final List<Appointment> recent;
  final PastAppointmentsQuery query;
  final Widget Function(BuildContext context, Appointment appointment)
      itemBuilder;
  final String emptyMessage;
  final String? emptySubtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pastAppointmentsProvider(query);
    final olderAsync = ref.watch(provider);
    final older = olderAsync.value;
    final items = [...recent, ...?older?.items];
    final cs = Theme.of(context).colorScheme;

    // The first older page is still on its way, or failed.
    final Widget? pending = older != null
        ? null
        : olderAsync.hasError
            ? AsyncView(
                value: olderAsync,
                onRetry: () => ref.invalidate(provider),
                builder: (_) => const SizedBox.shrink(),
              )
            : const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );

    if (items.isEmpty && pending == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 56, color: cs.outline),
            const SizedBox(height: 16),
            Text(emptyMessage, style: Theme.of(context).textTheme.titleMedium),
            if (emptySubtitle != null) ...[
              const SizedBox(height: 4),
              Text(emptySubtitle!, style: TextStyle(color: cs.outline)),
            ],
          ],
        ),
      );
    }

    final footer = pending ??
        (older!.hasMore || older.error != null
            ? LoadMoreFooter(
                loading: older.loadingMore,
                error: older.error,
                onLoadMore: () => ref.read(provider.notifier).loadMore(),
              )
            : null);

    return CenteredScroll(
      maxWidth: ContentWidth.list,
      padding: padding,
      builder: (padding) => ListView.separated(
        padding: padding,
        itemCount: items.length + (footer == null ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) =>
            i == items.length ? footer! : itemBuilder(context, items[i]),
      ),
    );
  }
}
