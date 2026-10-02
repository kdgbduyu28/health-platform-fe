import 'turnstile.dart';

const supported = false;

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
    throw UnsupportedError('Turnstile needs a browser');
