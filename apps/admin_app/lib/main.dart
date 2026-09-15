import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import 'app/app.dart';

Future<void> main() async {
  await initializeHealthPlatform();
  runApp(
    ProviderScope(
      // The only thing a build decides is which app it is. Which clinic it
      // shows comes from whoever signs in.
      overrides: [appRoleProvider.overrideWithValue(AppRole.admin)],
      child: const AdminApp(),
    ),
  );
}
