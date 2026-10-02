import 'print_html_stub.dart'
    if (dart.library.js_interop) 'print_html_web.dart' as impl;

/// Opens the browser's print dialog on [html], a whole page, where the user
/// prints it or saves it as a PDF. The page's `<title>` is the name offered
/// for the PDF. Relative URLs in it resolve against the app's base URL.
///
/// False outside a browser, where there is no print dialog to open.
bool printHtml(String html) => impl.printHtml(html);
