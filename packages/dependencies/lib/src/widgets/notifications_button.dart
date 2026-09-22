import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/app_notification.dart';
import '../providers/clinic_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// A bell for an app bar: the unread count, and the inbox on tap.
class NotificationsButton extends ConsumerWidget {
  const NotificationsButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      tooltip: 'Notifications',
      color: color,
      onPressed: () => showNotificationsSheet(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_none),
      ),
    );
  }
}

Future<void> showNotificationsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _NotificationsSheet(),
    );

class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final app = ref.watch(appRoleProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Notifications',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (unread > 0)
                  TextButton(
                    onPressed: () => ref
                        .read(healthRepositoryProvider)
                        .markNotificationsRead(app),
                    child: const Text('Mark all read'),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PushSettingsCard(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncView(
              value: ref.watch(notificationsProvider),
              onRetry: () => ref.invalidate(notificationsProvider),
              builder: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nothing yet. Updates about visits and bills '
                          'show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) =>
                          _NotificationTile(notification: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: n.isRead ? cs.surfaceContainerHighest : cs.primaryContainer,
        child: Icon(n.icon,
            color: n.isRead ? cs.onSurfaceVariant : cs.onPrimaryContainer),
      ),
      title: Text(n.title,
          style: TextStyle(
              fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.body),
          const SizedBox(height: 2),
          Text(_ago(n.createdAt),
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ],
      ),
      isThreeLine: true,
      onTap: () {
        if (!n.isRead) {
          ref
              .read(healthRepositoryProvider)
              .markNotificationsRead(n.app, ids: [n.id]);
        }
        final link = n.link;
        final router = GoRouter.of(context);
        Navigator.pop(context);
        if (link != null) router.go(link);
      },
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return DateFormat('EEEE').format(t);
  return DateFormat('MMM d').format(t);
}

/// Turns push notifications on or off for this browser, or says why it
/// cannot.
class PushSettingsCard extends ConsumerWidget {
  const PushSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(pushSettingsProvider);
    final notifier = ref.read(pushSettingsProvider.notifier);
    // A failed turn-on leaves no value behind; offer to try again.
    final state = async.value ?? (async.hasError ? PushState.off : null);

    final (icon, text, action) = switch (state) {
      PushState.on => (
          Icons.notifications_active_outlined,
          'Push notifications are on for this device.',
          TextButton(onPressed: notifier.disable, child: const Text('Turn off')),
        ),
      PushState.off => (
          Icons.notifications_off_outlined,
          'Get these on this device even when the app is closed.',
          FilledButton.tonal(
              onPressed: notifier.enable, child: const Text('Turn on')),
        ),
      PushState.blocked => (
          Icons.block,
          'Notifications are blocked for this site. Allow them in your '
              'browser\'s site settings.',
          null,
        ),
      PushState.needsHomeScreen => (
          Icons.ios_share,
          'On iPhone, tap Share → Add to Home Screen, open the app from '
              'there, then turn notifications on.',
          null,
        ),
      PushState.unsupported || null => (
          Icons.info_outline,
          'This browser cannot show push notifications. Check back here for '
              'updates.',
          null,
        ),
    };

    if (async.isLoading) {
      return const LinearProgressIndicator();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
              if (action != null) ...[const SizedBox(width: 8), action],
            ],
          ),
          if (async.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text(describeError(async.error!),
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
