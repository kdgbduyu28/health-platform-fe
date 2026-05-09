import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import 'router.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicType = ref.watch(clinicTypeProvider);
    return MaterialApp.router(
      title: '${clinicType.clinicName} — Admin',
      theme: buildClinicTheme(clinicType),
      routerConfig: adminRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
