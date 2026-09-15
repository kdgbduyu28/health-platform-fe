import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clinic.dart';
import '../providers/clinic_provider.dart';
import '../theme/brand.dart';

/// The current clinic's mark and name, for an app bar title.
///
/// When the user belongs to more than one clinic in this app, the title is
/// also the switcher: tap it to pick another clinic, and the whole app —
/// data and theme — follows.
class ClinicTitle extends ConsumerWidget {
  const ClinicTitle({super.key, this.style, this.markSize = 28});

  final TextStyle? style;

  /// Keep this at or under the text's line height where the title shares a
  /// collapsed app bar with a second line.
  final double markSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;
    final clinics = ref.watch(myClinicsProvider).value ?? const <Clinic>[];
    final canSwitch = clinics.length > 1;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClinicMark(clinic: clinic, size: markSize),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            clinic?.name ?? '',
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (canSwitch) ...[
          const SizedBox(width: 2),
          const Icon(Icons.expand_more),
        ],
      ],
    );

    if (!canSwitch) return content;

    return Semantics(
      button: true,
      label: 'Switch clinic',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showClinicSwitcher(context, ref),
        child: content,
      ),
    );
  }
}

/// A sheet listing every clinic this user can use the current app at.
Future<void> showClinicSwitcher(BuildContext context, WidgetRef ref) {
  final clinics = ref.read(myClinicsProvider).value ?? const <Clinic>[];
  final currentId = ref.read(currentClinicIdProvider);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Switch clinic',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          for (final clinic in clinics)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: ClinicMark(clinic: clinic, size: 36),
              title: Text(clinic.name),
              subtitle: Text(clinic.typeName),
              trailing: clinic.id == currentId
                  ? Icon(Icons.check,
                      color: Theme.of(sheetContext).colorScheme.primary)
                  : null,
              onTap: () {
                ref.read(selectedClinicIdProvider.notifier).select(clinic.id);
                Navigator.pop(sheetContext);
              },
            ),
        ],
      ),
    ),
  );
}
