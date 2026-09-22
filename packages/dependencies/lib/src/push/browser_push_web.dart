import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_push.dart';

BrowserPush createBrowserPush() => _WebPush();

const _worker = 'push_sw.js';
const _scope = './push/';

class _WebPush implements BrowserPush {
  @override
  bool get supported =>
      web.window.has('PushManager') &&
      web.window.has('Notification') &&
      web.window.navigator.has('serviceWorker');

  @override
  bool get needsHomeScreenInstall {
    if (supported) return false;
    final ua = userAgent;
    return ua.contains('iPhone') || ua.contains('iPad');
  }

  @override
  String get permission =>
      web.window.has('Notification') ? web.Notification.permission : 'denied';

  @override
  String get userAgent => web.window.navigator.userAgent;

  web.ServiceWorkerContainer get _workers => web.window.navigator.serviceWorker;

  Future<web.ServiceWorkerRegistration?> _existing() =>
      _workers.getRegistration(_scope).toDart;

  /// Registers push_sw.js and waits for it to be active: a push
  /// subscription needs an active worker, and `serviceWorker.ready` never
  /// settles for one that does not control the page.
  Future<web.ServiceWorkerRegistration> _registration() async {
    final reg = await _existing() ??
        await _workers
            .register(_worker.toJS, web.RegistrationOptions(scope: _scope))
            .toDart;
    for (var i = 0; reg.active == null && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (reg.active == null) {
      throw StateError('The notification service did not start. Reload and try again.');
    }
    return reg;
  }

  @override
  Future<PushKeys?> current() async {
    if (!supported) return null;
    final reg = await _existing();
    if (reg == null) return null;
    final sub = await reg.pushManager.getSubscription().toDart;
    return sub == null ? null : _keys(sub);
  }

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async {
    if (!supported) return null;
    if (permission != 'granted') {
      final answer = (await web.Notification.requestPermission().toDart).toDart;
      if (answer != 'granted') return null;
    }
    final reg = await _registration();
    final existing = await reg.pushManager.getSubscription().toDart;
    if (existing != null) return _keys(existing);
    final sub = await reg.pushManager
        .subscribe(web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: _base64UrlBytes(vapidPublicKey).toJS,
        ))
        .toDart;
    return _keys(sub);
  }

  @override
  Future<String?> unsubscribe() async {
    if (!supported) return null;
    final reg = await _existing();
    final sub = await reg?.pushManager.getSubscription().toDart;
    if (sub == null) return null;
    final endpoint = sub.endpoint;
    await sub.unsubscribe().toDart;
    return endpoint;
  }

  @override
  void onNotificationOpened(void Function(String link) open) {
    if (!web.window.navigator.has('serviceWorker')) return;
    _workers.addEventListener(
      'message',
      (web.MessageEvent event) {
        final data = event.data;
        if (data == null || !data.isA<JSObject>()) return;
        final message = data as JSObject;
        final type = message['type'];
        final link = message['link'];
        if (type.isA<JSString>() &&
            (type as JSString).toDart == 'open-link' &&
            link.isA<JSString>()) {
          open((link as JSString).toDart);
        }
      }.toJS,
    );
  }
}

PushKeys _keys(web.PushSubscription sub) => PushKeys(
      endpoint: sub.endpoint,
      p256dh: _base64Url(sub.getKey('p256dh')),
      auth: _base64Url(sub.getKey('auth')),
    );

String _base64Url(JSArrayBuffer? buffer) => buffer == null
    ? ''
    : base64Url.encode(buffer.toDart.asUint8List()).replaceAll('=', '');

Uint8List _base64UrlBytes(String key) =>
    base64Url.decode(key.padRight((key.length + 3) ~/ 4 * 4, '='));
