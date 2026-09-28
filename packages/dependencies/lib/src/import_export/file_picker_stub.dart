import 'file_picker.dart';

// Tests and non-web builds: there is no browser to pick a file with.
Future<PickedTextFile?> pickTextFile(String accept) async => null;
