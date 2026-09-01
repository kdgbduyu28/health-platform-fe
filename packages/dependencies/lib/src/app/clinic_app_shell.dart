import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/clinic_theme.dart';
import '../widgets/sign_in_screen.dart';

/// The outer shell shared by all four apps: clinic theming, plus the gate that
/// keeps the router out of reach until someone is signed in.
///
/// The gate is not decoration. Every table is deny-by-default in the database,
/// so a signed-out session can read nothing at all — without this the apps
/// would render their full navigation over uniformly empty lists.
class ClinicAppShell extends ConsumerWidget {
  const ClinicAppShell({
    super.key,
    required this.appName,
    required this.routerConfig,
    this.allowSignUp = false,
  });

  final String appName;
  final RouterConfig<Object> routerConfig;

  /// Patients may create their own account; staff accounts are provisioned by
  /// an admin, since the database will not let a signup choose its own role.
  final bool allowSignUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicType = ref.watch(clinicTypeProvider);
    final theme = buildClinicTheme(clinicType);

    if (!ref.watch(isSignedInProvider)) {
      return MaterialApp(
        title: clinicType.clinicName,
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: SignInScreen(appName: appName, allowSignUp: allowSignUp),
      );
    }

    return MaterialApp.router(
      title: clinicType.clinicName,
      theme: theme,
      routerConfig: routerConfig,
      debugShowCheckedModeBanner: false,
    );
  }
}
