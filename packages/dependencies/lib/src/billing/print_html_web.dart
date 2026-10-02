import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.HTMLIFrameElement? _frame;

// A hidden frame rather than a new tab: popup blockers leave it alone, and
// the app stays where it was behind the dialog.
bool printHtml(String html) {
  _frame?.remove();
  final base = web.document.baseURI;
  final page = html.replaceFirst('<head>', '<head><base href="$base">');

  final frame = web.HTMLIFrameElement()
    ..setAttribute('aria-hidden', 'true')
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '0'
    ..style.height = '0'
    ..style.border = '0';
  _frame = frame;

  frame.onload = ((web.Event _) {
    final win = frame.contentWindow;
    if (win == null) return;
    // Some browsers name the PDF after the app's tab, not the frame.
    final title = web.document.title;
    final printTitle = frame.contentDocument?.title ?? '';
    if (printTitle.isNotEmpty) web.document.title = printTitle;
    void done() {
      web.document.title = title;
    }

    win.addEventListener('afterprint', ((web.Event _) => done()).toJS);
    win.focus();
    win.print();
    // Where print() does not block, afterprint restores the title; where it
    // does, it has returned by now. Either way the frame stays until the
    // next print, as Safari still reads it after print() returns.
    Future<void>.delayed(const Duration(seconds: 2), done);
  }).toJS;

  frame.srcdoc = page.toJS;
  web.document.body?.append(frame);
  return true;
}
