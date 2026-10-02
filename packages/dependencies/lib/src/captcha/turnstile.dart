import 'turnstile_stub.dart'
    if (dart.library.js_interop) 'turnstile_web.dart' as impl;

/// Cloudflare Turnstile can run here: true in the web build, false in tests
/// and non-web builds, where the human check is simply off.
bool get turnstileSupported => impl.supported;

/// One Turnstile widget on the page, rendered into its own platform view.
///
/// Turnstile hands out single-use tokens that Supabase Auth checks with
/// Cloudflare before it signs anyone in, signs anyone up or sends a reset
/// code. The widget re-issues one by itself when a token expires.
abstract class TurnstileWidget {
  /// The platform view type to show with `HtmlElementView(viewType: …)`.
  String get viewType;

  /// Throws the current token away and fetches a new one.
  void reset();

  /// Takes the widget off the page for good.
  void remove();
}

TurnstileWidget createTurnstile({
  required String siteKey,
  required String action,
  required bool alwaysVisible,
  required bool dark,
  required void Function(String token) onToken,
  required void Function() onExpired,
  required void Function(String message) onError,
  required void Function(bool interactive) onInteractive,
}) =>
    impl.createTurnstile(
      siteKey: siteKey,
      action: action,
      alwaysVisible: alwaysVisible,
      dark: dark,
      onToken: onToken,
      onExpired: onExpired,
      onError: onError,
      onInteractive: onInteractive,
    );
