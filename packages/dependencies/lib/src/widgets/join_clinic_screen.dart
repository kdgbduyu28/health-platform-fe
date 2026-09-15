import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import 'async_view.dart';

/// Where a patient attaches their account to a clinic, using the code the
/// clinic gave them.
///
/// Shown in two ways. As the whole app, when a signed-in patient belongs to no
/// clinic yet — there is nothing else they could see. And pushed from the
/// profile screen, to add another clinic; then it closes itself on success.
class JoinClinicScreen extends ConsumerStatefulWidget {
  const JoinClinicScreen({super.key});

  @override
  ConsumerState<JoinClinicScreen> createState() => _JoinClinicScreenState();
}

class _JoinClinicScreenState extends ConsumerState<JoinClinicScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from your clinic.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final clinicId = await ref.read(healthRepositoryProvider).joinClinic(code);
      // The new chart is what makes the clinic visible at all, so both lists
      // have to be refetched — and the clinic just joined becomes current.
      ref.invalidate(myPatientsProvider);
      ref.invalidate(visibleClinicsProvider);
      ref.read(selectedClinicIdProvider.notifier).select(clinicId);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGate = !Navigator.of(context).canPop();

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
                  const Center(child: ClinicMark(size: 72)),
                  const SizedBox(height: 24),
                  Text(
                    isGate ? 'Join your clinic' : 'Add another clinic',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the code your clinic gave you. Once you have '
                    'joined, you can book and see your appointments there.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _code,
                    autofocus: true,
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
                      hintText: 'CLINIC CODE',
                      hintStyle: TextStyle(letterSpacing: 2, fontSize: 16),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error),
                    ),
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
                        : const Text('Join clinic'),
                  ),
                  if (isGate) ...[
                    const SizedBox(height: 8),
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
