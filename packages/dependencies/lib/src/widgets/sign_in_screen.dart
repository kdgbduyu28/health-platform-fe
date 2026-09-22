import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clinic.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import 'async_view.dart';
import 'password_reset_screen.dart';

/// Shared sign-in for all four apps.
///
/// Every app offers sign-up, because an account grants nothing by itself.
/// Access comes afterwards, per clinic: a patient joins with the clinic's code,
/// and a staff member is added by that clinic's admin — who can only add an
/// account that already exists.
///
/// Reached through a clinic's link (`/:clinic/sign-in`), it wears that
/// clinic's name and logo; at `/` nobody is known yet, so it is unbranded.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    required this.appName,
    this.initialSignUp = false,
  });

  final String appName;

  /// Open on the create-account form — the landing page's "Create account".
  final bool initialSignUp;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late bool _isSignUp = widget.initialSignUp;
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
          final app = ref.read(appRoleProvider);
          final email = _email.text.trim();
          final nextStep = app.takesStaffCodes
              ? ' Then sign in and enter the staff code your clinic gave you.'
              : app.isStaff
                  ? ' Then ask your clinic administrator to add $email.'
                  : '';
          setState(() => _notice =
              'Account created. If email confirmation is on, check your inbox '
              'before signing in.$nextStep');
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
    final app = ref.watch(appRoleProvider);
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
                    _Header(
                      appName: widget.appName,
                      clinic: ref.watch(routeBrandClinicProvider),
                    ),
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
                    if (!_isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PasswordResetScreen(
                                        initialEmail: _email.text.trim(),
                                      ),
                                    ),
                                  ),
                          child: const Text('Forgot password?'),
                        ),
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
                    if (app.isStaff) ...[
                      const SizedBox(height: 8),
                      Text(
                        app.takesStaffCodes
                            ? 'New staff: create your account, sign in, then '
                                'enter the staff code from your clinic\'s admin.'
                            : 'New staff: create your account, then ask your '
                                'clinic administrator to add you.',
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
  const _Header({required this.appName, this.clinic});

  final String appName;
  final Clinic? clinic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        ClinicMark(clinic: clinic, size: 72),
        const SizedBox(height: 16),
        Text(
          clinic == null ? 'Sign in to your clinic' : 'Sign in to ${clinic!.name}',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          appName,
          style: TextStyle(color: cs.onSurfaceVariant, letterSpacing: 0.5),
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
