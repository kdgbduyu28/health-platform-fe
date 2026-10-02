import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../captcha/human_check.dart';
import '../models/clinic.dart';
import '../legal/legal_document.dart';
import '../legal/privacy_policy.dart';
import '../legal/terms.dart';
import '../providers/clinic_provider.dart';
import '../providers/preferences_provider.dart';
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
  // Most devices sign in the same person every time.
  late final _email =
      TextEditingController(text: ref.read(preferencesProvider).lastEmail);
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _check = HumanCheckController();

  late bool _isSignUp = widget.initialSignUp;
  bool _busy = false;

  /// The Terms and Privacy Policy box on the create-account form. Never
  /// ticked for them: the law wants it read, not skipped past.
  bool _agreed = false;
  String? _error;
  String? _notice;

  /// Wrong sign-ins on this screen. Past [_quietTries] the human check comes
  /// out into view. Supabase checks a token on every attempt either way; this
  /// only decides whether the person sees it happen.
  int _failedSignIns = 0;
  static const _quietTries = 3;

  bool get _showCheck => _isSignUp || _failedSignIns >= _quietTries;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _check.dispose();
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
    String? captchaToken;
    try {
      captchaToken = await _check.token();
      if (_isSignUp) {
        await repo.signUp(
          _email.text.trim(),
          _password.text,
          _fullName.text.trim(),
          captchaToken: captchaToken,
          privacyPolicyVersion: PrivacyPolicy.version,
          termsVersion: TermsAndConditions.version,
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
        await repo.signIn(
          _email.text.trim(),
          _password.text,
          captchaToken: captchaToken,
        );
        await ref.read(preferencesProvider).setLastEmail(_email.text.trim());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!_isSignUp && e is AuthException) _failedSignIns++;
          _error = describeError(e);
          if (!_isSignUp && _failedSignIns >= _quietTries) {
            _error = '$_error\nToo many tries. Wait for the security check '
                'below to pass before you try again.';
          }
        });
      }
    } finally {
      // Each token is good for one request.
      if (captchaToken != null) _check.reset();
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
                    if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      _PoliciesBox(
                        value: _agreed,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _agreed = v),
                      ),
                    ],
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
                    HumanCheck(
                      controller: _check,
                      action: _isSignUp ? 'sign-up' : 'sign-in',
                      alwaysVisible: _showCheck,
                    ),
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

/// "I agree to the Terms and Conditions and have read the Privacy Policy",
/// with both a tap away. The form will not create the account until it is
/// ticked.
///
/// It is not consent to health information: a clinic asks for that on its
/// own form, later.
class _PoliciesBox extends StatelessWidget {
  const _PoliciesBox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget link(LegalDocument document) => InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LegalDocumentScreen(document: document),
            ),
          ),
          child: Text(
            document.title,
            style: TextStyle(
              color: cs.primary,
              decoration: TextDecoration.underline,
              decorationColor: cs.primary,
            ),
          ),
        );

    return FormField<bool>(
      initialValue: value,
      validator: (v) => v == true
          ? null
          : 'Tick the box to agree to the Terms and Conditions',
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (v) {
                        onChanged!(v ?? false);
                        field.didChange(v);
                      },
              ),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('I agree to the '),
                    link(TermsAndConditions.document),
                    const Text(' and have read the '),
                    link(PrivacyPolicy.document),
                  ],
                ),
              ),
            ],
          ),
          if (field.hasError)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(field.errorText!,
                  style: TextStyle(color: cs.error, fontSize: 12)),
            ),
        ],
      ),
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
