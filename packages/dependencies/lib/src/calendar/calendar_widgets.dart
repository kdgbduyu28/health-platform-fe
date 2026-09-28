import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../providers/clinic_provider.dart';
import '../widgets/async_view.dart';
import 'browser_links.dart';
import 'calendar_feed_provider.dart';
import 'calendar_links.dart';

/// "Add to calendar" for one upcoming visit: a Google Calendar link or an
/// .ics file, both made on the device. It does not follow a later move;
/// the sheet offers the feed, which does.
class AddToCalendarButton extends ConsumerWidget {
  const AddToCalendarButton({super.key, required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _showSheet(context, ref),
      icon: const Icon(Icons.event_available_outlined),
      label: const Text('Add to calendar'),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    final clinic = ref.read(clinicByIdProvider(appointment.clinicId));
    final origin = appOrigin();
    final event = VisitEvent.fromAppointment(
      appointment,
      clinic: clinic,
      appLink: origin == null || clinic == null
          ? null
          : '$origin/${clinic.slug}/appointments/${appointment.id}',
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Google Calendar'),
              subtitle: const Text('Opens Google Calendar to save it'),
              onTap: () {
                Navigator.pop(sheet);
                openExternal(googleCalendarLink(event));
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Apple Calendar, Outlook, others'),
              subtitle: const Text('Downloads an .ics file to open'),
              onTap: () {
                Navigator.pop(sheet);
                downloadTextFile('visit.ics', 'text/calendar', visitIcs(event));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('Keep all my visits in my calendar'),
              subtitle: const Text(
                  'Subscribe once; moved and cancelled visits update on their own'),
              onTap: () {
                Navigator.pop(sheet);
                showCalendarFeedSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Subscribing a calendar app to the account's feed, and resetting its URL.
Future<void> showCalendarFeedSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SafeArea(child: _CalendarFeedSheet()),
    );

class _CalendarFeedSheet extends ConsumerWidget {
  const _CalendarFeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(calendarFeedUrlProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your visits in your calendar',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Subscribe once and every visit, at every clinic you belong to, '
            'appears in your calendar. Moved and cancelled visits update on '
            'their own. Google Calendar checks for changes every few hours.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          switch (urlAsync) {
            AsyncData(value: final url?) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => openExternal(googleSubscribeLink(url)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Add to Google Calendar'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => openExternal(webcalUrl(url)),
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Apple Calendar or Outlook'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Link copied'),
                        behavior: SnackBarBehavior.floating,
                      ));
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Copy link for another app'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Anyone with this link can see your visit times, so '
                    'keep it to yourself. Visits show the clinic and doctor, '
                    'not what they are for.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _confirmReset(context, ref),
                      child: const Text('Reset link'),
                    ),
                  ),
                ],
              ),
            AsyncError(:final error) => Text(describeError(error),
                style: TextStyle(color: cs.error)),
            _ => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          },
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset calendar link?'),
        content: const Text(
            'The old link stops working at once. Any calendar subscribed to '
            'it stops updating; subscribe again with the new one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await resetCalendarFeed(ref);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(describeError(e)),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}
