import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import 'app/app.dart';

Future<void> main() async {
  await initializeHealthPlatform();
  runApp(
    ProviderScope(
      overrides: [clinicTypeProvider.overrideWithValue(ClinicType.pedia)],
      child: const AssistantApp(),
    ),
  );
}
