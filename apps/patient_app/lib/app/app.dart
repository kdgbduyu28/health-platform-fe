import 'package:flutter/material.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class PatientApp extends StatelessWidget {
  const PatientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ClinicAppShell(
      appName: 'Patient',
      routerConfig: patientRouter,
      allowSignUp: true,
    );
  }
}
