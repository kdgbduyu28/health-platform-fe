import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';
import 'staff_code_screen.dart';

enum _AccountAction { staffCode, changePassword, signOut }

/// The signed-in account's menu, for an app bar: who is signed in, change
/// password, sign out — and in the doctor and assistant apps, joining another
/// clinic with a staff code.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(currentUserProvider)?.email;
    final app = ref.watch(appRoleProvider);
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.staffCode:
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const StaffCodeScreen(),
            ));
          case _AccountAction.changePassword:
            showChangePasswordDialog(context);
          case _AccountAction.signOut:
            // Signing out drops every RLS grant; the shell returns to the
            // sign-in screen on its own.
            ref.read(healthRepositoryProvider).signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          enabled: false,
          child: Text(
            email ?? 'Signed in',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        const PopupMenuDivider(),
        if (app.takesStaffCodes)
          const PopupMenuItem(
            value: _AccountAction.staffCode,
            child: _MenuRow(Icons.add_business_outlined, 'Join another clinic'),
          ),
        const PopupMenuItem(
          value: _AccountAction.changePassword,
          child: _MenuRow(Icons.password_outlined, 'Change password'),
        ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: _MenuRow(Icons.logout, 'Sign out'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// Asks for a new password for the signed-in account and saves it.
Future<void> showChangePasswordDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );
  if (changed == true) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Password changed'),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).changePassword(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'At least 6 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              onFieldSubmitted: (_) => _save(),
              validator: (v) =>
                  v != _password.text ? 'The passwords do not match' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
