import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/patient.dart';
import '../providers/billing_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/tone.dart';
import 'account_menu.dart';
import 'async_view.dart';
import 'billing_widgets.dart';
import 'clinic_title.dart';
import 'ledger_view.dart';
import 'notifications_button.dart';

enum _Filter { unpaid, drafts, paid, all }

/// The clinic's bills and its ledger, for the front desk and admins.
///
/// Bills: what came in today, what is still owed, and every bill by state.
/// Ledger: gross, paid, pending, expenses and net over some days.
///
/// The package has no router; [onOpenInvoice] is how the app opens a bill
/// and [onOpenPrices] its price list.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, required this.onOpenInvoice, this.onOpenPrices});

  final void Function(String invoiceId) onOpenInvoice;
  final VoidCallback? onOpenPrices;

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

    return DefaultTabController(
      length: canBill ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: const ClinicTitle(page: 'Billing'),
          actions: [
            if (canBill && widget.onOpenPrices != null)
              IconButton(
                tooltip: 'Prices',
                icon: const Icon(Icons.sell_outlined),
                onPressed: widget.onOpenPrices,
              ),
            const NotificationsButton(),
            const AccountMenuButton(),
            const SizedBox(width: 8),
          ],
          bottom: canBill
              ? const TabBar(tabs: [Tab(text: 'Bills'), Tab(text: 'Ledger')])
              : null,
        ),
        body: TabBarView(
          children: [
            _bills(context, async, canBill, summary),
            if (canBill) LedgerView(onOpenInvoice: widget.onOpenInvoice),
          ],
        ),
      ),
    );
  }

  Widget _bills(BuildContext context, AsyncValue<List<Invoice>> async,
      bool canBill, BillingSummary? summary) {
    return Scaffold(
      floatingActionButton: canBill
          ? FloatingActionButton.extended(
              onPressed: _newBill,
              icon: const Icon(Icons.add),
              label: const Text('New bill'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => invalidateBilling(ref),
        child: LayoutBuilder(builder: (context, box) {
          // Columns once there is room: patient, what for, number, date,
          // total, balance and state line up to scan down.
          _wide = box.maxWidth >= Breakpoints.twoPane;
          return CustomScrollView(
          slivers: [
            _centered(SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    _Stat(
                      label: 'Collected today',
                      value: summary == null ? '—' : formatPeso(summary.collected),
                      color: InvoiceStatus.paid.color.readableIn(context),
                    ),
                    const SizedBox(width: 8),
                    _Stat(
                      label: summary == null
                          ? 'Owed'
                          : 'Owed on ${summary.unpaidCount} '
                              '${summary.unpaidCount == 1 ? 'bill' : 'bills'}',
                      value: summary == null ? '—' : formatPeso(summary.outstanding),
                      color: InvoiceStatus.issued.color.readableIn(context),
                    ),
                  ],
                ),
              ),
            )),
            _centered(SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search by patient or bill number…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
            )),
            _centered(SliverToBoxAdapter(
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
            )),
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
        );
        }),
      ),
    );
  }

  bool _wide = false;

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
    if (_wide) {
      return [
        _centered(const SliverToBoxAdapter(child: _BillRowHeading())),
        _centered(SliverList.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) => _BillRow(
            invoice: shown[i],
            last: i == shown.length - 1,
            onTap: () => widget.onOpenInvoice(shown[i].id),
          ),
        )),
      ];
    }
    return [
      _centered(SliverList.separated(
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
      )),
    ];
  }

  /// One column of bills, centred; wider once it is a table.
  Widget _centered(Widget sliver) => SliverCentered(
        maxWidth: (_wide ? ContentWidth.wide : ContentWidth.list) + 32,
        padding: EdgeInsets.zero,
        sliver: sliver,
      );

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

// ── Bills as a table (tablet and up) ────────────────────────────────────────

const _billFlex = [4, 4, 3, 3, 3, 3];
const _statusWidth = 104.0;

/// Lays [cells] out on the table's columns: the flexes above, then the state.
Widget _billCells(List<Widget> cells) => Row(
      children: [
        for (final (i, c) in cells.indexed)
          i < _billFlex.length
              ? Expanded(flex: _billFlex[i], child: c)
              : SizedBox(width: _statusWidth, child: c),
      ],
    );

class _BillRowHeading extends StatelessWidget {
  const _BillRowHeading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700, color: cs.onSurfaceVariant);
    Widget h(String t, {bool end = false}) => Text(t,
        style: style, textAlign: end ? TextAlign.end : TextAlign.start);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: _billCells([
        h('Patient'),
        h('For'),
        h('Bill'),
        h('Date'),
        h('Total', end: true),
        h('Balance', end: true),
        Padding(padding: const EdgeInsets.only(left: 16), child: h('State')),
      ]),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({required this.invoice, required this.onTap, required this.last});

  final Invoice invoice;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = invoice;
    final when = v.visitAt ?? v.issuedAt ?? v.createdAt;
    final muted = TextStyle(color: cs.onSurfaceVariant);
    final radius = last
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : BorderRadius.zero;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: radius,
        border: Border(
            bottom: last
                ? BorderSide.none
                : BorderSide(color: cs.outlineVariant.withAlpha(120))),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: _billCells([
            Text(v.patient?.name ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(v.label, style: muted),
            Text(DateFormat('MMM d, y').format(when), style: muted),
            Text(formatPeso(v.total),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              v.isOpen ? formatPeso(v.balance) : '—',
              textAlign: TextAlign.end,
              style: v.isOpen
                  ? TextStyle(color: cs.error, fontWeight: FontWeight.w600)
                  : muted,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InvoiceStatusChip(status: v.status),
              ),
            ),
          ]),
        ),
      ),
    );
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
              // Searched in the database; the first few matches only.
              child: AsyncView(
                value: ref.watch(patientSearchProvider(_query)),
                onRetry: () => ref.invalidate(patientSearchProvider(_query)),
                builder: (shown) {
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
