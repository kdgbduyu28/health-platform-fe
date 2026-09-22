import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/staff_invite.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import 'async_view.dart';

/// Where a doctor or assistant asks to join a clinic with the single-use code
/// its admin gave them, and waits for the admin to approve.
///
/// Shown as the whole app when the account has no clinic in this app yet, and
/// pushed from the account menu to join another one.
class StaffCodeScreen extends ConsumerStatefulWidget {
  const StaffCodeScreen({super.key});

  @override
  ConsumerState<StaffCodeScreen> createState() => _StaffCodeScreenState();
}

class _StaffCodeScreenState extends ConsumerState<StaffCodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the staff code from your clinic.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final app = ref.read(appRoleProvider);
      await ref.read(healthRepositoryProvider).redeemStaffInvite(code, app);
      ref.invalidate(myStaffRequestsProvider);
      _code.clear();
      if (mounted) {
        setState(() => _notice = 'Request sent. You will get access as soon '
            'as an admin at the clinic approves it.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Approval creates a membership (and a doctor's roster row), so every one
  /// of those has to be refetched for the clinic to appear.
  ///
  /// Approval at the clinic in the URL moves the router on by itself. A code
  /// can belong to a different clinic, though, so if that is where access
  /// arrived, go to `/` and let the router pick it.
  Future<void> _refresh() async {
    ref.invalidate(myStaffRequestsProvider);
    ref.invalidate(myMembershipsProvider);
    ref.invalidate(myDoctorsProvider);
    ref.invalidate(visibleClinicsProvider);
    final clinics = await ref.read(myClinicsProvider.future);
    if (!mounted || clinics.isEmpty || Navigator.of(context).canPop()) return;
    final here = ref.read(routeClinicSlugProvider);
    if (!clinics.any((c) => c.slug == here)) GoRouter.of(context).go('/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGate = !Navigator.of(context).canPop();
    final email = ref.watch(currentUserProvider)?.email ?? 'this account';
    final requests =
        ref.watch(myStaffRequestsProvider).value ?? const <StaffRequest>[];
    final anyWaiting = requests.any((r) =>
        r.status == StaffInviteStatus.pending ||
        r.status == StaffInviteStatus.approved);

    return Scaffold(
      appBar: isGate ? null : AppBar(title: const Text('Join a clinic')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClinicMark(
                      clinic: isGate ? ref.watch(routeBrandClinicProvider) : null,
                      size: 72,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isGate ? 'Join your clinic' : 'Join another clinic',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the staff code your clinic\'s admin gave you. Each '
                    'code works once, and an admin approves the request '
                    'before you can see anything.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _code,
                    autofocus: requests.isEmpty,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(
                      letterSpacing: 4,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: 'STAFF CODE',
                      hintStyle: TextStyle(letterSpacing: 2, fontSize: 16),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.error)),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.primary)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send request'),
                  ),
                  if (requests.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      'Your requests',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final request in requests) _RequestTile(request),
                  ],
                  if (anyWaiting) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check again'),
                    ),
                  ],
                  if (isGate) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Signed in as $email',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => ref.read(healthRepositoryProvider).signOut(),
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile(this.request);

  final StaffRequest request;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color, text) = switch (request.status) {
      StaffInviteStatus.pending => (
          Icons.hourglass_top,
          cs.tertiary,
          'Waiting for approval'
        ),
      StaffInviteStatus.approved => (
          Icons.check_circle_outline,
          cs.primary,
          'Approved — tap Check again'
        ),
      StaffInviteStatus.rejected => (
          Icons.block,
          cs.error,
          'Not approved'
        ),
      StaffInviteStatus.revoked => (
          Icons.undo,
          cs.onSurfaceVariant,
          'Withdrawn by the clinic'
        ),
      StaffInviteStatus.open => (
          Icons.hourglass_empty,
          cs.onSurfaceVariant,
          'Not sent'
        ),
    };

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(request.clinicName),
        subtitle: Text('${request.role.displayName} · $text'),
      ),
    );
  }
}
