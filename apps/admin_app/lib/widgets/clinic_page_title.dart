import 'package:flutter/material.dart';
import 'package:api_sdk/api_sdk.dart';

/// App bar title for the admin tabs: which tab this is, and which clinic it is
/// showing.
///
/// An admin may run several clinics, and every tab shows one clinic's data, so
/// every tab says which — and lets them switch without going back to the
/// dashboard.
class ClinicPageTitle extends StatelessWidget {
  const ClinicPageTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        ClinicTitle(
          markSize: 20,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
