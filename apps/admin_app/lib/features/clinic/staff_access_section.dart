import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

/// New staff waiting for approval, and the single-use codes still unused.
///
/// Full admins and branch admins both run this: the database lets either one
/// issue doctor and assistant codes at their clinic and decide the requests.
class StaffAccessSection extends ConsumerWidget {
  const StaffAccessSection({super.key});

  Future<void> _newCode(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(AppRole, String)>(
      context: context,
      builder: (_) => const _NewCodeDialog(),
    );
    if (result == null || !context.mounted) return;
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final (role, label) = result;
      final invite = await ref.read(healthRepositoryProvider).createStaffInvite(
            clinicId: clinicId,
            role: role,
            label: label,
          );
      ref.invalidate(staffInvitesProvider);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => _CodeIssuedDialog(invite: invite),
        );
      }
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, StaffInvite invite) async {
    final ok = await _confirm(
      context,
      title: 'Cancel code ${invite.code}?',
      message: 'It stops working straight away. You can issue a new one.',
      action: 'Cancel code',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(healthRepositoryProvider).revokeStaffInvite(invite.id);
      ref.invalidate(staffInvitesProvider);
      _snack(messenger, 'Code cancelled');
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    StaffInvite request, {
    required bool approve,
  }) async {
    final clinic = ref.read(currentClinicProvider).value;
    final role = request.role.displayName.toLowerCase();
    String? doctorId;
    String? specialty;

    if (approve && request.role == AppRole.doctor) {
      final choice = await showDialog<(String?, String?)>(
        context: context,
        builder: (_) => _ApproveDoctorDialog(request: request),
      );
      if (choice == null) return;
      (doctorId, specialty) = choice;
    } else {
      final ok = await _confirm(
        context,
        title: approve
            ? 'Approve ${request.applicant}?'
            : 'Decline ${request.applicant}?',
        message: approve
            ? 'They join ${clinic?.name ?? 'this clinic'} as $role and can see '
                'its appointments and patients straight away.'
            : 'They will not get access. The code cannot be used again; '
                'issue a new one if this was a mistake.',
        action: approve ? 'Approve' : 'Decline',
        destructive: !approve,
      );
      if (!ok) return;
    }
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(healthRepositoryProvider).decideStaffRequest(
            inviteId: request.id,
            approve: approve,
            doctorId: doctorId,
            specialty: specialty,
          );
      ref.invalidate(staffInvitesProvider);
      ref.invalidate(staffProvider);
      ref.invalidate(doctorsProvider);
      _snack(
        messenger,
        approve
            ? '${request.applicant} joined as $role'
            : 'Request from ${request.applicant} declined',
      );
    } catch (e) {
      _snack(messenger, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitesAsync = ref.watch(staffInvitesProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Staff requests',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () => _newCode(context, ref),
                icon: const Icon(Icons.key_outlined),
                label: const Text('New code'),
              ),
            ],
          ),
        ),
        AsyncView(
          value: invitesAsync,
          onRetry: () => ref.invalidate(staffInvitesProvider),
          builder: (invites) {
            final now = DateTime.now();
            final pending = [
              for (final i in invites)
                if (i.status == StaffInviteStatus.pending) i,
            ];
            final unused = [
              for (final i in invites)
                if (i.status == StaffInviteStatus.open && !i.isExpired(now)) i,
            ];

            if (pending.isEmpty && unused.isEmpty) {
              return Text(
                'Give each new doctor or assistant their own code. They enter '
                'it after creating an account, and their request shows up '
                'here for you to approve.',
                style: TextStyle(color: cs.onSurfaceVariant),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final request in pending)
                  _RequestCard(
                    request: request,
                    onApprove: () =>
                        _decide(context, ref, request, approve: true),
                    onDecline: () =>
                        _decide(context, ref, request, approve: false),
                  ),
                if (unused.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(
                      'Unused codes',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  for (final invite in unused)
                    _UnusedCodeCard(
                      invite: invite,
                      onRevoke: () => _revoke(context, ref, invite),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onDecline,
  });

  final StaffInvite request;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final details = [
      'Wants to join as ${request.role.displayName.toLowerCase()}',
      if (request.redeemerEmail != null) request.redeemerEmail!,
      if (request.label != null) 'code issued for ${request.label}',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.tertiaryContainer,
                child: Icon(Icons.hourglass_top,
                    color: cs.onTertiaryContainer, size: 20),
              ),
              title: Text(request.applicant),
              subtitle: Text(details.join(' · ')),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(onPressed: onDecline, child: const Text('Decline')),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnusedCodeCard extends StatelessWidget {
  const _UnusedCodeCard({required this.invite, required this.onRevoke});

  final StaffInvite invite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final details = [
      invite.role.displayName,
      if (invite.label != null) 'for ${invite.label}',
      'expires ${DateFormat('MMM d').format(invite.expiresAt)}',
    ];

    return Card(
      child: ListTile(
        leading: const Icon(Icons.key_outlined),
        title: Text(
          invite.code,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
        subtitle: Text(details.join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: invite.code));
                _snack(messenger, 'Code copied');
              },
            ),
            IconButton(
              tooltip: 'Cancel code',
              icon: const Icon(Icons.block),
              onPressed: onRevoke,
            ),
          ],
        ),
      ),
    );
  }
}

/// Returns (role, label), or null if cancelled.
class _NewCodeDialog extends StatefulWidget {
  const _NewCodeDialog();

  @override
  State<_NewCodeDialog> createState() => _NewCodeDialogState();
}

class _NewCodeDialogState extends State<_NewCodeDialog> {
  final _label = TextEditingController();
  AppRole _role = AppRole.doctor;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('New staff code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AppRole>(
            segments: const [
              ButtonSegment(value: AppRole.doctor, label: Text('Doctor')),
              ButtonSegment(value: AppRole.assistant, label: Text('Assistant')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Who is it for? (optional)',
              hintText: 'e.g. Dr. Reyes',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'One code per person. It works once and expires in 7 days.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop<(AppRole, String)>(
              context, (_role, _label.text.trim())),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _CodeIssuedDialog extends StatelessWidget {
  const _CodeIssuedDialog({required this.invite});

  final StaffInvite invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final who = invite.label ?? 'the new ${invite.role.displayName.toLowerCase()}';

    return AlertDialog(
      title: const Text('Staff code ready'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  invite.code,
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
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: invite.code)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Give this to $who. They create an account in the '
            '${invite.role.displayName} app, sign in, and enter it. It works '
            'once and expires ${DateFormat('MMM d').format(invite.expiresAt)}. '
            'You approve them here afterwards.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Approving a doctor also puts them on the roster: link a roster entry the
/// clinic already has, or create one. Returns (doctorId, specialty) — exactly
/// one of them set — or null if cancelled.
class _ApproveDoctorDialog extends ConsumerStatefulWidget {
  const _ApproveDoctorDialog({required this.request});

  final StaffInvite request;

  @override
  ConsumerState<_ApproveDoctorDialog> createState() =>
      _ApproveDoctorDialogState();
}

class _ApproveDoctorDialogState extends ConsumerState<_ApproveDoctorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _specialty = TextEditingController();

  /// Null means "create a new roster entry".
  String? _doctorId;

  @override
  void dispose() {
    _specialty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unlinked = [
      for (final d in ref.watch(doctorsProvider).value ?? const <Doctor>[])
        if (d.profileId == null) d,
    ];

    Widget option({
      required String? id,
      required String title,
      String? subtitle,
    }) {
      final selected = _doctorId == id;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        selected: selected,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: () => setState(() => _doctorId = id),
      );
    }

    return AlertDialog(
      title: Text('Approve ${widget.request.applicant}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Which roster entry is theirs? Patients book against the '
                'roster, so an entry the clinic already has keeps its '
                'appointments and schedule.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 8),
              for (final doctor in unlinked)
                option(
                  id: doctor.id,
                  title: doctor.name,
                  subtitle: doctor.specialty,
                ),
              option(id: null, title: 'Add a new roster entry'),
              if (_doctorId == null)
                TextFormField(
                  controller: _specialty,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Specialty',
                    hintText: 'e.g. Orthodontics',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter their specialty'
                      : null,
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop<(String?, String?)>(
              context,
              _doctorId == null
                  ? (null, _specialty.text.trim())
                  : (_doctorId, null),
            );
          },
          child: const Text('Approve'),
        ),
      ],
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
          child: const Text('Back'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? Theme.of(ctx).colorScheme.error : null,
            minimumSize: const Size(0, 40),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
