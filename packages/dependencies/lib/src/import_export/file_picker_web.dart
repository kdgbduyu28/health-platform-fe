import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'file_picker.dart';

Future<PickedTextFile?> pickTextFile(String accept) {
  final done = Completer<PickedTextFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.addEventListener(
      'change',
      ((web.Event _) {
        final file = input.files?.item(0);
        if (file == null) {
          if (!done.isCompleted) done.complete(null);
        } else {
          _read(file, done);
        }
      }).toJS);
  // Closing the dialog without a file (browsers that report it).
  input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!done.isCompleted) done.complete(null);
      }).toJS);
  input.click();
  return done.future;
}

Future<void> _read(web.File file, Completer<PickedTextFile?> done) async {
  try {
    final buffer = await file.arrayBuffer().toDart;
    if (!done.isCompleted) {
      done.complete((name: file.name, text: decodeTextFile(buffer.toDart.asUint8List())));
    }
  } catch (e, st) {
    if (!done.isCompleted) done.completeError(e, st);
  }
}
