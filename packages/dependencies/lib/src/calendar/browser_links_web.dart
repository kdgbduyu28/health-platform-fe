import 'dart:js_interop';

import 'package:web/web.dart' as web;

void openExternal(String url) {
  // webcal:// hands off to the calendar app; a new tab would stay blank.
  if (url.startsWith('webcal:')) {
    web.window.location.href = url;
  } else {
    web.window.open(url, '_blank', 'noopener');
  }
}

void downloadTextFile(String fileName, String mimeType, String contents) {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser a moment to start the download before the URL goes.
  Future<void>.delayed(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
}
