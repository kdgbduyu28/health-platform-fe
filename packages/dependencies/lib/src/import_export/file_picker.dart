import 'dart:convert';
import 'dart:typed_data';

import 'file_picker_stub.dart'
    if (dart.library.js_interop) 'file_picker_web.dart' as impl;

/// A file the person picked, as text.
typedef PickedTextFile = ({String name, String text});

/// Asks the browser for one file (by default a CSV) and reads it. Null if
/// they cancel, and always outside a browser.
Future<PickedTextFile?> pickTextFile({String accept = '.csv,text/csv'}) =>
    impl.pickTextFile(accept);

/// A spreadsheet's bytes as text. UTF-8 normally; Excel on Windows still
/// saves "CSV" in the old Western encoding, where "Peña" is not valid UTF-8,
/// so that falls back to Latin-1 instead of turning the ñ into �.
String decodeTextFile(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}
