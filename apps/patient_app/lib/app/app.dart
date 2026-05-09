import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class PatientApp extends ConsumerWidget {
  const PatientApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicType = ref.watch(clinicTypeProvider);
    return MaterialApp.router(
      title: clinicType.clinicName,
      theme: buildClinicTheme(clinicType),
      routerConfig: patientRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
