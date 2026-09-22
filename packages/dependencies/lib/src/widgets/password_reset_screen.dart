import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// Self-service password reset, pushed from the sign-in screen.
///
/// Two steps: email a code, then enter it with a new password. A code rather
/// than a link, because a reset link only works in the browser tab that asked
/// for it (the PKCE verifier lives there) and needs every app's URL on the
/// redirect allow-list, while a code works from any device the email opens on.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;

  /// The code has been spent and the user is signed in; only the new password
  /// is left to save. A retry must not verify the code again.
  bool _verified = false;

  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref
          .read(healthRepositoryProvider)
          .sendPasswordResetCode(_email.text);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _notice = 'If ${_email.text.trim()} has an account, a code is on '
              'its way. It can take a minute — check your spam folder too.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    // Read before any await: once the gate lifts, the shell swaps this whole
    // screen out and `ref` is gone.
    final repo = ref.read(healthRepositoryProvider);
    final gate = ref.read(passwordResetInProgressProvider.notifier);
    try {
      if (!_verified) {
        gate.start();
        await repo.verifyPasswordResetCode(_email.text, _code.text);
        _verified = true;
      }
      await repo.changePassword(_password.text);
      // Signed in with the new password: lifting the gate opens the app.
      gate.finish();
    } catch (e) {
      if (!_verified) gate.finish();
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaves after the code was verified but the password was not saved. The
  /// session the code opened is closed, so nobody is left signed in on a
  /// password they never chose.
  Future<void> _abandon() async {
    final repo = ref.read(healthRepositoryProvider);
    final gate = ref.read(passwordResetInProgressProvider.notifier);
    final navigator = Navigator.of(context);
    await repo.signOut();
    gate.finish();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !_verified,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _abandon();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_reset, size: 56, color: cs.primary),
                      const SizedBox(height: 16),
                      Text(
                        _codeSent
                            ? 'Enter the code from your email and choose a '
                                'new password.'
                            : 'Enter the email you sign in with. We will send '
                                'you a code to reset your password.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _email,
                        readOnly: _codeSent,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        onFieldSubmitted: (_) => _codeSent ? null : _sendCode(),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email'
                            : null,
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _code,
                          readOnly: _verified,
                          keyboardType: TextInputType.number,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                            labelText: 'Code from the email',
                            prefixIcon: Icon(Icons.pin_outlined),
                          ),
                          validator: (v) =>
                              RegExp(r'^\d{6,10}$').hasMatch(v?.trim() ?? '')
                                  ? null
                                  : 'Enter the code from the email',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'New password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'At least 6 characters'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onFieldSubmitted: (_) => _reset(),
                          validator: (v) => v != _password.text
                              ? 'The passwords do not match'
                              : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.error)),
                      ],
                      if (_notice != null) ...[
                        const SizedBox(height: 16),
                        Text(_notice!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.primary)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed:
                            _busy ? null : (_codeSent ? _reset : _sendCode),
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_codeSent ? 'Set new password' : 'Send code'),
                      ),
                      if (_codeSent && !_verified) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _sendCode,
                          child: const Text('Send a new code'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _codeSent = false;
                                    _notice = null;
                                    _error = null;
                                  }),
                          child: const Text('Use a different email'),
                        ),
                      ],
                      if (_verified) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _abandon,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
