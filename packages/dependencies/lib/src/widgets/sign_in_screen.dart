import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clinic_type.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// Shared sign-in for all four apps.
///
/// Sign-up is offered only where it makes sense — a patient can create their
/// own account, but staff accounts are provisioned by an admin, because the
/// database refuses to let anyone choose their own role at signup.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    required this.appName,
    this.allowSignUp = false,
  });

  final String appName;
  final bool allowSignUp;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Two entry points reach this — the button and the password field's
    // onFieldSubmitted — so it has to be re-entrant-safe. A second
    // signInWithPassword issues a fresh token that invalidates the first,
    // which 401s any request already in flight before the app recovers.
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final repo = ref.read(healthRepositoryProvider);
    try {
      if (_isSignUp) {
        await repo.signUp(
          _email.text.trim(),
          _password.text,
          _fullName.text.trim(),
        );
        if (mounted) {
          setState(() => _notice =
              'Account created. If email confirmation is on, check your inbox '
              'before signing in.');
        }
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicType = ref.watch(clinicTypeProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
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
                    _Header(clinicType: clinicType, appName: widget.appName),
                    const SizedBox(height: 32),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _fullName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'At least 6 characters'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _Banner(text: _error!, color: cs.error, icon: Icons.error_outline),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      _Banner(
                        text: _notice!,
                        color: cs.primary,
                        icon: Icons.info_outline,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    if (widget.allowSignUp) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _isSignUp = !_isSignUp;
                                  _error = null;
                                  _notice = null;
                                }),
                        child: Text(_isSignUp
                            ? 'I already have an account'
                            : 'New here? Create an account'),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(
                        'Staff accounts are created by your clinic '
                        'administrator.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.clinicType, required this.appName});

  final ClinicType clinicType;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, cs.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(clinicType.icon, size: 36, color: cs.onPrimary),
        ),
        const SizedBox(height: 16),
        Text(
          clinicType.clinicName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          appName,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
