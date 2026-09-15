import 'package:flutter/material.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class DoctorApp extends StatelessWidget {
  const DoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClinicAppShell(
      appName: 'Doctor',
      routerConfig: doctorRouter,
    );
  }
}
