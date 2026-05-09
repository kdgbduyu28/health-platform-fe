import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';
import 'app/app.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [clinicTypeProvider.overrideWithValue(ClinicType.dental)],
      child: const AdminApp(),
    ),
  );
}
