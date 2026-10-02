import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../billing/print_html.dart';
import '../billing/statement.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../providers/clinic_provider.dart';
import 'billing_widgets.dart';

/// Asks which of [patient]'s bills — one per visit — to put on a statement,
/// then opens the print dialog on it, to print or save as a PDF.
///
/// [invoices] as the patient's bills provider returns them, newest first.
/// Voided bills are not offered. The newest bill starts ticked, since the
/// usual ask is a receipt for the visit just finished.
Future<void> showPrintStatementSheet(
  BuildContext context, {
  required Patient patient,
  required List<Invoice> invoices,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PrintStatementSheet(patient: patient, invoices: invoices),
  );
}

/// Opens the print dialog on a statement of [invoices] straight away. For a
/// bill's own page, where there is nothing to choose.
void printStatement(
  BuildContext context,
  WidgetRef ref, {
  required Patient patient,
  required List<Invoice> invoices,
}) {
  final clinic = ref.read(currentClinicProvider).value;
  if (clinic == null) return;
  final opened = printHtml(buildStatementHtml(
    clinic: clinic,
    patient: patient,
    invoices: invoices,
  ));
  if (!opened) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('Printing works in the web app.'),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _PrintStatementSheet extends ConsumerStatefulWidget {
  const _PrintStatementSheet({required this.patient, required this.invoices});

  final Patient patient;
  final List<Invoice> invoices;

  @override
  ConsumerState<_PrintStatementSheet> createState() =>
      _PrintStatementSheetState();
}

class _PrintStatementSheetState extends ConsumerState<_PrintStatementSheet> {
  late final List<Invoice> _bills = [
    for (final v in widget.invoices)
      if (v.status != InvoiceStatus.voided) v,
  ];
  late final Set<String> _picked = {
    if (_bills.isNotEmpty) _bills.first.id,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chosen = [
      for (final v in _bills)
        if (_picked.contains(v.id)) v,
    ];
    final total = chosen.fold<double>(0, (s, v) => s + v.total);
    final allPicked = _bills.isNotEmpty && chosen.length == _bills.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Print statement',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Pick the visits to include. Each shows its items, discounts, '
            'payments and balance. From the print dialog you can print it '
            'or save it as a PDF.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_bills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No bills to print.',
                  style: TextStyle(color: cs.outline)),
            )
          else ...[
            CheckboxListTile(
              value: allPicked
                  ? true
                  : chosen.isEmpty
                      ? false
                      : null,
              tristate: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('All visits (${_bills.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onChanged: (_) => setState(() {
                if (allPicked) {
                  _picked.clear();
                } else {
                  _picked.addAll(_bills.map((v) => v.id));
                }
              }),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in _bills)
                    CheckboxListTile(
                      value: _picked.contains(v.id),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(v.title),
                      subtitle: Text([
                        DateFormat('MMM d, y')
                            .format(v.visitAt ?? v.issuedAt ?? v.createdAt),
                        v.label,
                      ].join(' · ')),
                      secondary: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatPeso(v.total),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          InvoiceStatusChip(status: v.status),
                        ],
                      ),
                      onChanged: (on) => setState(() => on == true
                          ? _picked.add(v.id)
                          : _picked.remove(v.id)),
                    ),
                ],
              ),
            ),
          ],
          if (chosen.any((v) => v.isDraft))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Drafts print as estimates: their amounts may still change.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: chosen.isEmpty
                ? null
                : () {
                    printStatement(context, ref,
                        patient: widget.patient, invoices: chosen);
                    Navigator.pop(context);
                  },
            icon: const Icon(Icons.print_outlined),
            label: Text(chosen.isEmpty
                ? 'Print'
                : 'Print ${chosen.length} '
                    '${chosen.length == 1 ? 'visit' : 'visits'} · '
                    '${formatPeso(total)}'),
          ),
        ],
      ),
    );
  }
}
