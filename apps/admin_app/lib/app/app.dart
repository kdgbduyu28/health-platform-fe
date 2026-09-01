import 'package:flutter/material.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClinicAppShell(
      appName: 'Admin',
      routerConfig: adminRouter,
      allowSignUp: false,
    );
  }
}
