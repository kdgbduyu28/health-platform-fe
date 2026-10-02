import 'dart:async';

import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import 'turnstile.dart';

/// The "are you human" check in front of sign-in, sign-up and password reset.
///
/// Supabase Auth refuses those three requests without a fresh Cloudflare
/// Turnstile token once CAPTCHA protection is on for the project (see the
/// backend README), so the check is enforced by the server, not by this form.
/// With no site key configured, or outside a browser, it is off: [token]
/// answers null and [HumanCheck] draws nothing.
class HumanCheckController extends ChangeNotifier {
  HumanCheckController({this.siteKey = SupabaseConfig.turnstileSiteKey});

  final String siteKey;

  bool get enabled => siteKey.isNotEmpty && turnstileSupported;

  TurnstileWidget? _widget;
  String? _token;
  Completer<String?>? _waiting;

  /// Why the check could not finish, for the widget to show.
  String? get error => _error;
  String? _error;

  /// Cloudflare wants a click. Only then does a hidden check need showing.
  bool get interactive => _interactive;
  bool _interactive = false;

  /// The token for the next auth request, or null when the check is off.
  ///
  /// Tokens are single-use: this hands the current one over, and [reset]
  /// must follow the request that spent it. Usually one is ready by the time
  /// the form is filled in; if not, this waits for it.
  ///
  /// Never throws. If the check failed or has not finished, the request goes
  /// without a token and Supabase decides: while CAPTCHA is off there, a
  /// blocked or broken widget cannot lock anyone out; once it is on, Supabase
  /// refuses and the person is told to let the check finish.
  Future<String?> token({Duration timeout = const Duration(seconds: 15)}) async {
    if (!enabled || _error != null) return null;
    if (_token case final ready?) {
      _token = null;
      return ready;
    }
    final waiting = _waiting ??= Completer<String?>();
    try {
      return await waiting.future.timeout(timeout);
    } on TimeoutException {
      if (identical(_waiting, waiting)) _waiting = null;
      return null;
    }
  }

  /// Fetches a new token after one was spent (or refused).
  void reset() {
    _token = null;
    _widget?.reset();
  }

  void _attach(TurnstileWidget widget) {
    _widget = widget;
    _token = null;
    _error = null;
    _interactive = false;
  }

  void _detach(TurnstileWidget widget) {
    if (identical(_widget, widget)) _widget = null;
  }

  void _gotToken(String token) {
    _error = null;
    if (_waiting case final waiting?) {
      _waiting = null;
      waiting.complete(token);
    } else {
      _token = token;
    }
    notifyListeners();
  }

  void _lostToken() {
    _token = null;
    notifyListeners();
  }

  void _failed(String message) {
    _token = null;
    _error = message;
    if (_waiting case final waiting?) {
      _waiting = null;
      waiting.complete(null);
    }
    notifyListeners();
  }

  void _setInteractive(bool value) {
    _interactive = value;
    notifyListeners();
  }
}

/// Where a [HumanCheckController]'s Turnstile widget sits in a form.
///
/// [alwaysVisible] shows Cloudflare's "Verifying… / Success" box. Without it
/// the check runs unseen and only appears if Cloudflare wants a click, which
/// is how sign-in stays quiet until someone gets the password wrong a few
/// times. Changing [action] or [alwaysVisible] renders a new widget, because
/// Turnstile fixes both when it renders.
class HumanCheck extends StatefulWidget {
  const HumanCheck({
    super.key,
    required this.controller,
    required this.action,
    this.alwaysVisible = true,
  });

  final HumanCheckController controller;

  /// Shows up in Cloudflare's analytics: `sign-in`, `sign-up`, `reset`.
  final String action;

  final bool alwaysVisible;

  @override
  State<HumanCheck> createState() => _HumanCheckState();
}

class _HumanCheckState extends State<HumanCheck> {
  TurnstileWidget? _turnstile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than in initState: the widget's theme follows the app's.
    if (_turnstile == null && widget.controller.enabled) _render();
  }

  @override
  void didUpdateWidget(HumanCheck old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.action != widget.action ||
        old.alwaysVisible != widget.alwaysVisible) {
      _remove(old.controller);
      if (widget.controller.enabled) _render();
    }
  }

  @override
  void dispose() {
    _remove(widget.controller);
    super.dispose();
  }

  void _render() {
    final controller = widget.controller;
    late final TurnstileWidget turnstile;
    // A replaced widget can still call back; only the current one counts.
    bool current() => identical(_turnstile, turnstile);
    turnstile = createTurnstile(
      siteKey: controller.siteKey,
      action: widget.action,
      alwaysVisible: widget.alwaysVisible,
      dark: Theme.of(context).brightness == Brightness.dark,
      onToken: (t) => current() ? controller._gotToken(t) : null,
      onExpired: () => current() ? controller._lostToken() : null,
      onError: (m) => current() ? controller._failed(m) : null,
      onInteractive: (i) => current() ? controller._setInteractive(i) : null,
    );
    _turnstile = turnstile;
    controller._attach(turnstile);
  }

  void _remove(HumanCheckController controller) {
    final turnstile = _turnstile;
    if (turnstile == null) return;
    _turnstile = null;
    controller._detach(turnstile);
    turnstile.remove();
  }

  void _retry() {
    _remove(widget.controller);
    setState(_render);
  }

  @override
  Widget build(BuildContext context) {
    final turnstile = _turnstile;
    if (turnstile == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final shown = widget.alwaysVisible || widget.controller.interactive;
        final error = widget.controller.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kept on the page at 1px while hidden: the check still has to
            // run, and a platform view that is not laid out never starts.
            Padding(
              padding: EdgeInsets.only(top: shown ? 16 : 0),
              child: SizedBox(
                height: shown ? 65 : 1,
                child: HtmlElementView(
                  key: ValueKey(turnstile.viewType),
                  viewType: turnstile.viewType,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
