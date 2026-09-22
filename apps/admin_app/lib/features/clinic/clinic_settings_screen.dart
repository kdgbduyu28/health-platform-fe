import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import '../../widgets/clinic_page_title.dart';
import 'staff_access_section.dart';

/// The clinic's own settings, run by its admins: how it presents itself, how
/// patients get in, and who works there.
///
/// All of it is self-service by design. The database lets an admin change
/// exactly these things for their own clinic — not its type, slug or active
/// status, which stay with the platform operator.
class ClinicSettingsScreen extends ConsumerWidget {
  const ClinicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const ClinicPageTitle('Clinic settings'),
        actions: const [
              NotificationsButton(),
              AccountMenuButton(),
              SizedBox(width: 8),
            ],
      ),
      body: clinic == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _DetailsCard(clinic: clinic),
                const SizedBox(height: 24),
                const _SectionTitle('Bookings'),
                const _BookingsCard(),
                const SizedBox(height: 24),
                const _SectionTitle('Patient join code'),
                _JoinCodeCard(clinic: clinic),
                const SizedBox(height: 24),
                const StaffAccessSection(),
                const SizedBox(height: 24),
                const _StaffSection(),
              ],
            ),
    );
  }
}

void _snack(ScaffoldMessengerState messenger, String text) {
  messenger.showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  minimumSize: const Size(0, 40),
                )
              : FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ── Details ─────────────────────────────────────────────────────────────────

class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({required this.clinic});

  final Clinic clinic;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final changes = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _EditDetailsDialog(clinic: clinic),
    );
    if (changes == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(healthRepositoryProvider).updateClinic(clinic.id, changes);
      ref.invalidate(visibleClinicsProvider);
      _snack(messenger, 'Clinic details saved');
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClinicMark(clinic: clinic, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clinic.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        clinic.typeName,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit details',
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if (clinic.contactPhone != null || clinic.address != null)
              const Divider(height: 24),
            if (clinic.contactPhone != null)
              _InfoLine(icon: Icons.phone_outlined, text: clinic.contactPhone!),
            if (clinic.address != null)
              _InfoLine(icon: Icons.place_outlined, text: clinic.address!),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Returns the changed columns, or null if cancelled.
class _EditDetailsDialog extends StatefulWidget {
  const _EditDetailsDialog({required this.clinic});

  final Clinic clinic;

  @override
  State<_EditDetailsDialog> createState() => _EditDetailsDialogState();
}

class _EditDetailsDialogState extends State<_EditDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.clinic.name);
  late final _color = TextEditingController(
    text: widget.clinic.seedColor == null
        ? ''
        : toHexColor(widget.clinic.seedColor!),
  );
  late final _logo = TextEditingController(text: widget.clinic.logoUrl ?? '');
  late final _phone =
      TextEditingController(text: widget.clinic.contactPhone ?? '');
  late final _address =
      TextEditingController(text: widget.clinic.address ?? '');

  @override
  void dispose() {
    for (final c in [_name, _color, _logo, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final color = parseHexColor(_orNull(_color));
    Navigator.pop<Map<String, Object?>>(context, {
      'name': _name.text.trim(),
      'seed_color': color == null ? null : toHexColor(color),
      'logo_url': _orNull(_logo),
      'contact_phone': _orNull(_phone),
      'address': _orNull(_address),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clinic details'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Clinic name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _color,
                builder: (context, value, _) {
                  final preview = parseHexColor(value.text);
                  return TextFormField(
                    controller: _color,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Brand colour',
                      hintText: '#1F8A70',
                      helperText: 'Leave empty for the platform colour',
                      suffixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: preview ?? Colors.transparent,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return parseHexColor(v) == null
                          ? 'Use #RRGGBB, e.g. #1F8A70'
                          : null;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _logo,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Logo URL',
                  hintText: 'https://…',
                  helperText: 'A square image works best',
                ),
                validator: (v) {
                  final url = v?.trim() ?? '';
                  if (url.isEmpty) return null;
                  final ok = url.startsWith('https://') ||
                      url.startsWith(Brand.bundledAssetScheme);
                  return ok ? null : 'Use an https:// link';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ── Join code ───────────────────────────────────────────────────────────────

class _JoinCodeCard extends ConsumerWidget {
  const _JoinCodeCard({required this.clinic});

  final Clinic clinic;

  Future<void> _rotate(BuildContext context, WidgetRef ref) async {
    final hadCode = clinic.joinCode != null;
    if (hadCode) {
      final ok = await _confirm(
        context,
        title: 'Issue a new code?',
        message: 'The current code stops working immediately. Patients who '
            'have already joined are not affected.',
        action: 'New code',
      );
      if (!ok || !context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final code =
          await ref.read(healthRepositoryProvider).rotateJoinCode(clinic.id);
      ref.invalidate(visibleClinicsProvider);
      _snack(messenger,
          hadCode ? 'New code: $code' : 'Patients can join with $code');
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  Future<void> _turnOff(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Turn off joining by code?',
      message: 'Patients will not be able to join ${clinic.name} with a code '
          'until you turn it back on. Patients who have already joined are '
          'not affected.',
      action: 'Turn off',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(healthRepositoryProvider)
          .updateClinic(clinic.id, {'join_code': null});
      ref.invalidate(visibleClinicsProvider);
      _snack(messenger, 'Joining by code is off');
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = clinic.joinCode;
    const inline = Size(0, 40);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code == null
                  ? 'Patients cannot join ${clinic.name} on their own right '
                      'now. Staff can still register walk-ins.'
                  : 'Patients enter this code in the patient app to join '
                      '${clinic.name}.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (code != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      code,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy code',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: code));
                      _snack(messenger, 'Code copied');
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (code != null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: inline),
                    onPressed: () => _rotate(context, ref),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('New code'),
                  ),
                  TextButton(
                    onPressed: () => _turnOff(context, ref),
                    child: const Text('Turn off'),
                  ),
                ] else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: inline),
                    onPressed: () => _rotate(context, ref),
                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                    label: const Text('Turn on'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Staff ───────────────────────────────────────────────────────────────────

class _StaffSection extends ConsumerWidget {
  const _StaffSection();

  Future<void> _invite(BuildContext context, WidgetRef ref,
      {ClinicMembership? existing}) async {
    final result = await showDialog<(String, AppRole, bool)>(
      context: context,
      builder: (_) => _InviteDialog(
        existing: existing,
        canGrantAdmin: ref.read(isFullAdminProvider),
      ),
    );
    if (result == null || !context.mounted) return;

    final (email, role, branchLocked) = result;
    final roleName =
        branchLocked ? 'branch admin' : role.displayName.toLowerCase();
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(healthRepositoryProvider)
          .inviteStaff(
            clinicId: clinicId,
            email: email,
            role: role,
            branchLocked: branchLocked,
          );
      ref.invalidate(staffProvider);
      // The admin may have just changed their OWN role.
      ref.invalidate(myMembershipsProvider);
      _snack(
        messenger,
        existing == null
            ? '$email added as $roleName'
            : 'Role updated to $roleName',
      );
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, ClinicMembership member) async {
    final clinic = ref.read(currentClinicProvider).value;
    final name = member.fullName ?? member.email ?? 'this person';
    final ok = await _confirm(
      context,
      title: 'Remove $name?',
      message: 'They lose access to ${clinic?.name ?? 'this clinic'} straight '
          'away. Appointments and notes they worked on stay.',
      action: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(healthRepositoryProvider).removeStaff(
            clinicId: member.clinicId,
            profileId: member.profileId,
          );
      ref.invalidate(staffProvider);
      ref.invalidate(myMembershipsProvider);
      _snack(messenger, '$name removed');
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffProvider);
    final me = ref.watch(currentUserIdProvider);
    // A branch admin manages doctors and assistants, never admins.
    final isFullAdmin = ref.watch(isFullAdminProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          'Staff',
          action: TextButton.icon(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Add'),
          ),
        ),
        AsyncView(
          value: staffAsync,
          onRetry: () => ref.invalidate(staffProvider),
          builder: (staff) => Column(
            children: [
              for (final member in staff)
                Card(
                  child: ListTile(
                    onTap: isFullAdmin || member.role != AppRole.admin
                        ? () => _invite(context, ref, existing: member)
                        : null,
                    leading: CircleAvatar(
                      backgroundColor: cs.primaryContainer,
                      child: Text(
                        _initials(member.fullName ?? member.email ?? '?'),
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(member.fullName ?? member.email ?? 'Unknown'),
                    subtitle: Text([
                      member.roleLabel,
                      if (member.email != null) member.email!,
                    ].join(' · ')),
                    trailing: member.profileId == me
                        ? Text('You',
                            style: TextStyle(color: cs.onSurfaceVariant))
                        : !isFullAdmin && member.role == AppRole.admin
                        ? null
                        : IconButton(
                            tooltip: 'Remove from clinic',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _remove(context, ref, member),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (name.trim().isEmpty) return '?';
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return parts.first[0].toUpperCase();
  }
}

/// Adds someone, or changes an existing member's role. Returns
/// (email, role, branchLocked), or null if cancelled.
class _InviteDialog extends StatefulWidget {
  const _InviteDialog({this.existing, required this.canGrantAdmin});

  final ClinicMembership? existing;

  /// False for a branch admin, who may not hand out either kind of admin.
  final bool canGrantAdmin;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late AppRole _role = widget.existing?.role ?? AppRole.assistant;
  late bool _branchLocked = widget.existing?.branchLocked ?? false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(isEdit ? 'Change role' : 'Add staff'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              readOnly: isEdit,
              autofocus: !isEdit,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<AppRole>(
              segments: [
                const ButtonSegment(
                    value: AppRole.doctor, label: Text('Doctor')),
                const ButtonSegment(
                    value: AppRole.assistant, label: Text('Assistant')),
                if (widget.canGrantAdmin)
                  const ButtonSegment(
                      value: AppRole.admin, label: Text('Admin')),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_role == AppRole.admin) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _branchLocked,
                onChanged: (v) => setState(() => _branchLocked = v),
                title: const Text('Branch admin'),
                subtitle: const Text(
                  'Runs this clinic only. Cannot add or change admins, and '
                  'cannot be an admin at any other clinic.',
                ),
              ),
            ],
            if (!isEdit) ...[
              const SizedBox(height: 16),
              Text(
                'They need an account first: ask them to create one in any '
                'of the apps with this email, then add them here. Doctors '
                'and assistants can also join with a staff code.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop<(String, AppRole, bool)>(context, (
              _email.text.trim(),
              _role,
              _role == AppRole.admin && _branchLocked,
            ));
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

/// Where what patients can book is set up: who, what, and when not.
class _BookingsCard extends ConsumerWidget {
  const _BookingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doctors = ref.watch(rosterProvider).value;
    final services = ref.watch(catalogueProvider).value;
    final timeOff = ref.watch(timeOffProvider).value;
    String? count(List<Object>? list, String one, String many) => list == null
        ? null
        : '${list.length} ${list.length == 1 ? one : many}';

    Widget tile(IconData icon, String title, String? subtitle, String path) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushInClinic(path),
        );

    return Card(
      child: Column(
        children: [
          tile(Icons.badge_outlined, 'Doctors & hours',
              count(doctors, 'doctor', 'doctors'), '/settings/doctors'),
          const Divider(height: 1, indent: 56),
          tile(Icons.medical_services_outlined, 'Services & prices',
              count(services, 'service', 'services'), '/settings/services'),
          const Divider(height: 1, indent: 56),
          tile(Icons.event_busy_outlined, 'Closures & leave',
              timeOff == null
                  ? null
                  : timeOff.isEmpty
                      ? 'None coming up'
                      : '${timeOff.length} coming up',
              '/settings/closures'),
        ],
      ),
    );
  }
}
