import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invoice.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../providers/billing_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import 'account_menu.dart';
import 'async_view.dart';
import 'billing_widgets.dart';
import 'clinic_title.dart';
import 'notifications_button.dart';

enum _Filter { unpaid, drafts, paid, all }

/// The clinic's bills, for the front desk and admins: what came in today,
/// what is still owed, and every bill by state.
///
/// The package has no router; [onOpenInvoice] is how the app opens one.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, required this.onOpenInvoice});

  final void Function(String invoiceId) onOpenInvoice;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  _Filter _filter = _Filter.unpaid;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clinicInvoicesProvider);
    final canBill = ref.watch(canBillProvider).value ?? false;
    final today = DateUtils.dateOnly(DateTime.now());
    final summary =
        ref.watch(billingSummaryProvider((from: today, to: today))).value;

    return Scaffold(
      appBar: AppBar(
        title: const ClinicTitle(),
        actions: const [NotificationsButton(), AccountMenuButton(), SizedBox(width: 8)],
      ),
      floatingActionButton: canBill
          ? FloatingActionButton.extended(
              onPressed: _newBill,
              icon: const Icon(Icons.add),
              label: const Text('New bill'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => invalidateBilling(ref),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _Stat(
                      label: 'Collected today',
                      value: summary == null ? '—' : formatPeso(summary.collected),
                      color: InvoiceStatus.paid.color,
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      label: summary == null
                          ? 'Owed'
                          : 'Owed on ${summary.unpaidCount} '
                              '${summary.unpaidCount == 1 ? 'bill' : 'bills'}',
                      value: summary == null ? '—' : formatPeso(summary.outstanding),
                      color: InvoiceStatus.issued.color,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search by patient or bill number…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final f in _Filter.values) ...[
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.unpaid => 'Unpaid',
                          _Filter.drafts => 'Drafts',
                          _Filter.paid => 'Paid',
                          _Filter.all => 'All',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            if (!async.hasValue)
              SliverFillRemaining(
                child: AsyncView(
                  value: async,
                  onRetry: () => ref.invalidate(clinicInvoicesProvider),
                  builder: (_) => const SizedBox.shrink(),
                ),
              )
            else
              ..._list(async.requireValue),
            const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
          ],
        ),
      ),
    );
  }

  List<Widget> _list(List<Invoice> all) {
    final shown = all.where((v) {
      final inFilter = switch (_filter) {
        _Filter.unpaid => v.status == InvoiceStatus.issued,
        _Filter.drafts => v.status == InvoiceStatus.draft,
        _Filter.paid => v.status == InvoiceStatus.paid,
        _Filter.all => true,
      };
      if (!inFilter) return false;
      if (_query.isEmpty) return true;
      return (v.patient?.name.toLowerCase().contains(_query) ?? false) ||
          (v.number?.toLowerCase().contains(_query) ?? false);
    }).toList();

    if (shown.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              _query.isNotEmpty ? 'No bills match "$_query"' : 'Nothing here',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: InvoiceTile(
            invoice: shown[i],
            showPatient: true,
            onTap: () => widget.onOpenInvoice(shown[i].id),
          ),
        ),
      ),
    ];
  }

  /// A bill not tied to a visit — a retainer, a product. Most bills start
  /// from the visit instead.
  Future<void> _newBill() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (_) => const _PatientPicker(),
    );
    final clinicId = ref.read(currentClinicIdProvider);
    if (patient == null || clinicId == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref
          .read(healthRepositoryProvider)
          .createInvoice(clinicId: clinicId, patientId: patient.id);
      invalidateBilling(ref);
      widget.onOpenInvoice(id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(describeError(e)), behavior: SnackBarBehavior.floating));
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _PatientPicker extends ConsumerStatefulWidget {
  const _PatientPicker();

  @override
  ConsumerState<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<_PatientPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bill which patient?'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Name or phone',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: ref.watch(patientsProvider),
                onRetry: () => ref.invalidate(patientsProvider),
                builder: (patients) {
                  final shown = [
                    for (final p in patients)
                      if (_query.isEmpty ||
                          p.name.toLowerCase().contains(_query) ||
                          p.phone.contains(_query))
                        p,
                  ];
                  return ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(shown[i].name),
                      subtitle: Text(shown[i].phone),
                      onTap: () => Navigator.pop(context, shown[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
