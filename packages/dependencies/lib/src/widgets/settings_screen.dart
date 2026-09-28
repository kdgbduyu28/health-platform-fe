import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/adaptive_layout.dart';
import '../models/app_role.dart';
import '../models/dental_chart.dart';
import '../providers/clinic_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/supabase_providers.dart';
import 'account_menu.dart';
import 'async_view.dart';
import 'join_clinic_screen.dart';
import 'staff_code_screen.dart';
import 'staff_pin.dart';

/// `/:clinic/preferences`: how this app looks and what it tells you, plus the
/// account's own chores. The same page in all four apps; what is on it
/// follows the app ([appRoleProvider]) and the clinic.
///
/// Two kinds of setting live here, and the page says which is which:
///   this device   theme, text size, push, tooth numbering — in the browser's
///                 storage, so a shared front desk tablet keeps its own
///   your account  which notifications to get — in the database, so they
///                 follow the person to every device
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    final clinic = ref.watch(currentClinicProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CenteredScroll(
        maxWidth: ContentWidth.list,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        builder: (padding) => ListView(
          padding: padding,
          children: [
            const _AccountHeader(),
            const _SectionTitle('Appearance', 'On this device'),
            const _AppearanceCard(),
            const _SectionTitle('Notifications'),
            const _NotificationsCard(),
            if (clinic?.isDental ?? false) ...[
              const _SectionTitle('Dental chart', 'On this device'),
              const _DentalCard(),
            ],
            const _SectionTitle('Account'),
            _AccountCard(app: app),
            const _SectionTitle('About'),
            _AboutCard(app: app),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, [this.note]);

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700)),
          if (note != null) ...[
            const SizedBox(width: 8),
            Text(note!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ],
      ),
    );
  }
}

/// Who is signed in, and where.
class _AccountHeader extends ConsumerWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final profile = ref.watch(myProfileProvider).value;
    final email = ref.watch(currentUserProvider)?.email ?? '';
    final clinic = ref.watch(currentClinicProvider).value;
    final app = ref.watch(appRoleProvider);

    final name = profile?.fullName.isNotEmpty == true ? profile!.fullName : email;
    final where = [
      if (app.isStaff) app.displayName,
      if (clinic != null) clinic.name,
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primaryContainer,
              child: Text(profile?.initials ?? '?',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (name != email && email.isNotEmpty)
                    Text(email,
                        style: TextStyle(color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis),
                  if (where.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(where,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Appearance ──────────────────────────────────────────────────────────────

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final size = ref.watch(textSizeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Label('Theme'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Auto'),
                  tooltip: 'Follow this device',
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Dark'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.single),
            ),
            if (mode == ThemeMode.system)
              const _Hint('Switches with your device\'s light or dark setting.'),
            const SizedBox(height: 20),
            const _Label('Text size'),
            SegmentedButton<TextSize>(
              showSelectedIcon: false,
              segments: [
                for (final s in TextSize.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {size},
              onSelectionChanged: (s) =>
                  ref.read(textSizeProvider.notifier).set(s.single),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

// ── Notifications ───────────────────────────────────────────────────────────

class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final topics = NotificationTopic.forApp(ref.watch(appRoleProvider));
    final mutes = ref.watch(notificationMutesProvider);

    Future<void> toggle(String kind, bool on) async {
      try {
        await ref.read(notificationMutesProvider.notifier).setEnabled(kind, on);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not save: ${describeError(e)}'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PushTile(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Tell me about',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: cs.onSurface)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'For your account, on every device. Anything switched off here '
              'is neither shown in the inbox nor pushed.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          if (mutes.hasError && !mutes.hasValue)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'These choices could not be loaded. Everything is on.',
                      style: TextStyle(color: cs.error, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(notificationMutesProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            for (final t in topics)
              SwitchListTile(
                title: Text(t.label),
                subtitle: Text(t.description),
                value: !(mutes.value?.contains(t.kind) ?? false),
                onChanged: mutes.hasValue ? (on) => toggle(t.kind, on) : null,
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Push for this browser: a switch when there is a choice to make, and the
/// reason when there is not.
class _PushTile extends ConsumerWidget {
  const _PushTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(pushSettingsProvider);
    final notifier = ref.read(pushSettingsProvider.notifier);
    // A failed turn-on leaves no value behind; offer to try again.
    final state = async.value ?? (async.hasError ? PushState.off : null);

    final String subtitle = switch (state) {
      PushState.on => 'On for this device, even when the app is closed.',
      PushState.off => 'Off for this device. Turn on to get alerts when the '
          'app is closed.',
      PushState.blocked => 'Blocked for this site. Allow notifications in '
          'your browser\'s site settings, then come back.',
      PushState.needsHomeScreen => 'On iPhone, tap Share → Add to Home '
          'Screen, open the app from there, then turn this on.',
      PushState.unsupported => 'This browser cannot show push notifications. '
          'The inbox (the bell) still gets everything.',
      null => 'Checking this device…',
    };
    final canToggle = !async.isLoading &&
        (state == PushState.on || state == PushState.off);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(
            state == PushState.on
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: cs.primary,
          ),
          title: const Text('Push notifications'),
          subtitle: Text(subtitle),
          value: state == PushState.on,
          onChanged: canToggle
              ? (on) => on ? notifier.enable() : notifier.disable()
              : null,
        ),
        if (async.isLoading) const LinearProgressIndicator(minHeight: 2),
        if (async.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
            child: Text(describeError(async.error!),
                style: TextStyle(color: cs.error, fontSize: 12)),
          ),
      ],
    );
  }
}

// ── Dental ──────────────────────────────────────────────────────────────────

class _DentalCard extends ConsumerWidget {
  const _DentalCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numbering = ref.watch(toothNumberingProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Label('Tooth numbering'),
            SegmentedButton<ToothNumbering>(
              showSelectedIcon: false,
              segments: [
                for (final n in ToothNumbering.values)
                  ButtonSegment(value: n, label: Text(n.displayName)),
              ],
              selected: {numbering},
              onSelectionChanged: (s) =>
                  ref.read(toothNumberingProvider.notifier).set(s.single),
            ),
            _Hint(switch (numbering) {
              ToothNumbering.fdi =>
                'Two digits: quadrant, then tooth. Upper right molar is 18.',
              ToothNumbering.universal =>
                '1–32 from the upper right. Upper right molar is 1.',
            }),
          ],
        ),
      ),
    );
  }
}

// ── Account ─────────────────────────────────────────────────────────────────

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.app});

  final AppRole app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showChangePasswordDialog(context),
          ),
          if (app.registersPatients)
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Tablet PIN'),
              subtitle: const Text(
                  'Takes the tablet back after a patient fills in their form'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (await showSetStaffPinDialog(context)) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text('PIN saved'),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
            ),
          if (app == AppRole.patient)
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Join another clinic'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(const JoinClinicScreen()),
            ),
          if (app.takesStaffCodes)
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Join another clinic'),
              subtitle: const Text('With a staff code from its admin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(const StaffCodeScreen()),
            ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: cs.error),
            title: Text('Sign out', style: TextStyle(color: cs.error)),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Push notifications stop on this device until you sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    // Signing out drops every RLS grant; the router takes it from there.
    if (ok == true) await ref.read(healthRepositoryProvider).signOut();
  }
}

// ── About ───────────────────────────────────────────────────────────────────

class _AboutCard extends ConsumerWidget {
  const _AboutCard({required this.app});

  final AppRole app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.apps_outlined),
            title: Text('${app.displayName} app'),
            subtitle: clinic == null ? null : Text(clinic.name),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset this device\'s settings'),
            subtitle: const Text('Theme, text size and tooth numbering'),
            onTap: () async {
              await ref.read(preferencesProvider).resetDisplay();
              ref
                ..invalidate(themeModeProvider)
                ..invalidate(textSizeProvider)
                ..invalidate(toothNumberingProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Settings reset'),
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
        ],
      ),
    );
  }
}
