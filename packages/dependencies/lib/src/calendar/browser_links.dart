import 'browser_links_stub.dart'
    if (dart.library.js_interop) 'browser_links_web.dart' as impl;

/// Opens [url] in a new tab (or the app that handles it, for webcal://).
void openExternal(String url) => impl.openExternal(url);

/// Hands [contents] to the browser as a file download named [fileName].
/// On iPhone, a text/calendar file opens straight into "Add to Calendar".
void downloadTextFile(String fileName, String mimeType, String contents) =>
    impl.downloadTextFile(fileName, mimeType, contents);

/// Where the app is served from, for links back into it. Null outside a
/// browser.
String? appOrigin() {
  final base = Uri.base;
  return base.scheme == 'http' || base.scheme == 'https' ? base.origin : null;
}
