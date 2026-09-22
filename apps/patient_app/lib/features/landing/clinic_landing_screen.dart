import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';

/// `/:clinic` — the clinic's public page, for anyone with the link.
///
/// Everything here comes from `clinic_by_slug`, the one thing an anonymous
/// visitor may read: branding, contact details, services and doctors. What
/// it offers next depends on who is looking — a visitor can sign in or
/// create an account, a patient of the clinic can book, and a signed-in
/// account that has not joined yet is asked for the clinic's code. Joining
/// still takes that code: the page shows the clinic, it does not admit.
class ClinicLandingScreen extends ConsumerWidget {
  const ClinicLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slug = context.clinicSlug;
    final page = ref.watch(clinicPageProvider(slug));

    return Scaffold(
      body: AsyncView(
        value: page,
        onRetry: () => ref.invalidate(clinicPageProvider(slug)),
        // Null is an unknown clinic, which the router has already sent to
        // /not-found; this frame is on its way out.
        builder: (data) =>
            data == null ? const SizedBox.shrink() : _Landing(page: data),
      ),
    );
  }
}

class _Landing extends ConsumerWidget {
  const _Landing({required this.page});

  final ClinicPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = page.clinic;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(clinic: clinic),
                const SizedBox(height: 16),
                const _Actions(),
                if (page.services.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _SectionTitle('Services', count: page.services.length),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, s) in page.services.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 16),
                          ListTile(
                            leading: Icon(Icons.medical_services_outlined,
                                color: cs.primary),
                            title: Text(s.name),
                            trailing: Text(
                              '${s.durationMinutes} min',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (page.doctors.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _SectionTitle('Our doctors', count: page.doctors.length),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, d) in page.doctors.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          ListTile(
                            leading: DoctorAvatar(doctor: d, radius: 20),
                            title: Text(d.name),
                            subtitle: Text([
                              if (d.specialty.isNotEmpty) d.specialty,
                              if (d.availableWeekdays.isNotEmpty)
                                formatWeekdays(d.availableWeekdays),
                            ].join(' · ')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  'Powered by the ${clinic.name} patient app',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.clinic});

  final Clinic clinic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          ClinicMark(clinic: clinic, size: 88),
          const SizedBox(height: 16),
          Text(
            clinic.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Chip(
            avatar: Icon(clinic.icon, size: 16, color: cs.primary),
            label: Text(clinic.typeName),
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
            backgroundColor: cs.surface,
          ),
          if (clinic.address != null || clinic.contactPhone != null) ...[
            const SizedBox(height: 16),
            if (clinic.address case final address?)
              _ContactLine(icon: Icons.place_outlined, text: address),
            if (clinic.contactPhone case final phone?)
              _ContactLine(icon: Icons.call_outlined, text: phone),
          ],
        ],
      ),
    );
  }
}

class _ContactLine extends StatelessWidget {
  const _ContactLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: SelectableText(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

/// What this visitor can do next.
class _Actions extends ConsumerWidget {
  const _Actions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final isPatientHere = ref.watch(currentClinicProvider).value != null;
    final cs = Theme.of(context).colorScheme;

    final List<Widget> buttons;
    String? note;
    if (!signedIn) {
      buttons = [
        // The router asks them to sign in first, then brings them back.
        FilledButton.icon(
          onPressed: () => context.goInClinic('/book'),
          icon: const Icon(Icons.event_available),
          label: const Text('Book an appointment'),
        ),
        OutlinedButton(
          onPressed: () => context.goInClinic('/sign-in'),
          child: const Text('Sign in'),
        ),
        TextButton(
          onPressed: () => context.goInClinic('/sign-in?mode=sign-up'),
          child: const Text('Create account'),
        ),
      ];
      note = 'New patient? Create an account, then enter the code the clinic '
          'gives you.';
    } else if (isPatientHere) {
      buttons = [
        FilledButton.icon(
          onPressed: () => context.goInClinic('/book'),
          icon: const Icon(Icons.event_available),
          label: const Text('Book an appointment'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.goInClinic('/home'),
          icon: const Icon(Icons.calendar_today_outlined),
          label: const Text('My appointments'),
        ),
      ];
    } else {
      buttons = [
        FilledButton.icon(
          onPressed: () => context.goInClinic('/join'),
          icon: const Icon(Icons.vpn_key_outlined),
          label: const Text('Join with clinic code'),
        ),
        TextButton(
          onPressed: () => ref.read(healthRepositoryProvider).signOut(),
          child: const Text('Sign out'),
        ),
      ];
      note = 'You are signed in but have not joined this clinic yet. Ask the '
          'clinic for its code.';
    }

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: buttons,
        ),
        if (note != null) ...[
          const SizedBox(height: 12),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '$text ($count)',
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
