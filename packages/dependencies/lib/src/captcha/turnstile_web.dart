import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

import 'turnstile.dart';

const supported = true;

const _script =
    'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

TurnstileWidget createTurnstile({
  required String siteKey,
  required String action,
  required bool alwaysVisible,
  required bool dark,
  required void Function(String token) onToken,
  required void Function() onExpired,
  required void Function(String message) onError,
  required void Function(bool interactive) onInteractive,
}) {
  final options = JSObject()
    ..['sitekey'] = siteKey.toJS
    ..['action'] = action.toJS
    ..['theme'] = (dark ? 'dark' : 'light').toJS
    // Hidden until Cloudflare actually needs a click; always shown once the
    // screen wants the check to be seen (sign-up, reset, repeated failures).
    ..['appearance'] = (alwaysVisible ? 'always' : 'interaction-only').toJS
    ..['size'] = 'flexible'.toJS
    ..['refresh-expired'] = 'auto'.toJS
    ..['callback'] = ((JSString token) => onToken(token.toDart)).toJS
    ..['expired-callback'] = onExpired.toJS
    ..['error-callback'] = ((JSAny? code) {
      onError('The security check could not finish'
          '${code == null ? '' : ' (${code.dartify()})'}.');
    }).toJS
    ..['before-interactive-callback'] = (() => onInteractive(true)).toJS
    ..['after-interactive-callback'] = (() => onInteractive(false)).toJS;
  return _WebTurnstile(options, onError);
}

/// The Turnstile script, loaded once per page and only when a screen asks
/// for it, so signed-in pages never fetch it.
Future<_Api>? _loading;

Future<_Api> _api() => _loading ??= () {
      final done = Completer<_Api>();
      final script = web.HTMLScriptElement()..src = _script;
      script.onload = ((web.Event _) {
        done.complete(globalContext['turnstile'] as _Api);
      }).toJS;
      script.onerror = ((web.Event _) {
        _loading = null; // let the next widget try again
        done.completeError(StateError(
            'The security check could not load. Check your connection, or '
            'allow challenges.cloudflare.com if a content blocker is on.'));
      }).toJS;
      web.document.head!.append(script);
      return done.future;
    }();

extension type _Api._(JSObject _) implements JSObject {
  external JSString? render(web.HTMLElement container, JSObject options);
  external void reset(JSString widgetId);
  external void remove(JSString widgetId);
}

var _nextView = 0;

class _WebTurnstile implements TurnstileWidget {
  _WebTurnstile(JSObject options, void Function(String) onError)
      : viewType = 'turnstile-${_nextView++}' {
    final host = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => host);
    _mount(host, options).catchError((Object e) {
      onError(e is StateError ? e.message : '$e');
    });
  }

  @override
  final String viewType;

  _Api? _turnstile;
  JSString? _id;
  bool _removed = false;

  Future<void> _mount(web.HTMLDivElement host, JSObject options) async {
    final api = await _api();
    // Flutter attaches the view's element a frame or two after the factory
    // runs, and Turnstile's iframe will not start in a detached element.
    for (var i = 0; !host.isConnected && i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_removed || !host.isConnected) return;
    _turnstile = api;
    _id = api.render(host, options);
  }

  @override
  void reset() {
    if (_id case final id?) _turnstile?.reset(id);
  }

  @override
  void remove() {
    _removed = true;
    if (_id case final id?) _turnstile?.remove(id);
    _id = null;
  }
}
