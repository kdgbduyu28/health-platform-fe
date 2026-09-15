import 'package:flutter/material.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClinicAppShell(
      appName: 'Assistant',
      routerConfig: assistantRouter,
    );
  }
}
