import 'browser_push.dart';

BrowserPush createBrowserPush() => const _NoPush();

class _NoPush implements BrowserPush {
  const _NoPush();

  @override
  bool get supported => false;

  @override
  bool get needsHomeScreenInstall => false;

  @override
  String get permission => 'denied';

  @override
  String get userAgent => '';

  @override
  Future<PushKeys?> current() async => null;

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async => null;

  @override
  Future<String?> unsubscribe() async => null;

  @override
  void onNotificationOpened(void Function(String link) open) {}
}
