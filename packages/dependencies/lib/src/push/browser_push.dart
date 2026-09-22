import 'browser_push_stub.dart'
    if (dart.library.js_interop) 'browser_push_web.dart' as impl;

/// What a browser hands over when it subscribes to Web Push: where to send,
/// and the keys to encrypt for it. The send-push Edge Function needs all
/// three.
class PushKeys {
  const PushKeys({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}

/// This browser's Web Push, behind one small interface: the web build uses
/// the Push API; tests and non-web builds get a browser without it.
///
/// Pushes are shown by `web/push_sw.js`, a service worker registered under
/// `./push/` so it never competes with Flutter's own for the page.
abstract class BrowserPush {
  /// The Push API and notifications exist here. False on iPhone Safari
  /// unless the site was added to the home screen.
  bool get supported;

  /// An iPhone or iPad where adding the site to the home screen would turn
  /// push on.
  bool get needsHomeScreenInstall;

  /// `granted`, `denied` or `default` (not asked yet).
  String get permission;

  String get userAgent;

  /// The subscription this browser already holds, if any.
  Future<PushKeys?> current();

  /// Asks for permission if need be, then subscribes with the platform's
  /// VAPID public key. Null if the person said no.
  Future<PushKeys?> subscribe(String vapidPublicKey);

  /// Drops this browser's subscription. Returns its endpoint, if it had one.
  Future<String?> unsubscribe();

  /// Calls [open] with the link of a notification tapped while the app is
  /// already open, so it can navigate rather than open a second tab.
  void onNotificationOpened(void Function(String link) open);
}

BrowserPush createBrowserPush() => impl.createBrowserPush();
