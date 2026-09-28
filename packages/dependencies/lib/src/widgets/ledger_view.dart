import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/app_role.dart';
import '../models/invoice.dart';
import '../models/ledger.dart';
import '../models/money.dart';
import '../providers/billing_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/tone.dart';
import 'async_view.dart';

enum _Period { today, week, month, custom }

/// The clinic's money over some days: gross, paid, pending, expenses and net,
/// how it was paid, and every payment in and expense out behind them. For the
/// front desk and admins — the database refuses anyone else.
///
/// Every figure is the database's (`ledger_summary`); nothing is added up
/// here.
class LedgerView extends ConsumerStatefulWidget {
  const LedgerView({super.key, required this.onOpenInvoice});

  final void Function(String invoiceId) onOpenInvoice;

  @override
  ConsumerState<LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends ConsumerState<LedgerView> {
  _Period _period = _Period.today;
  DateTimeRange? _custom;

  BillingRange get _range {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_period) {
      _Period.today => (from: today, to: today),
      // Monday to today.
      _Period.week => (
          from: today.subtract(Duration(days: today.weekday - 1)),
          to: today
        ),
      _Period.month => (from: DateTime(today.year, today.month), to: today),
      _Period.custom => (
          from: _custom?.start ?? today,
          to: _custom?.end ?? today
        ),
    };
  }

  Future<void> _pickRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialDateRange: _custom ?? DateTimeRange(start: _range.from, end: _range.to),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final summary = ref.watch(ledgerSummaryProvider(range));
    final entries = ref.watch(ledgerEntriesProvider(range));
    final fmt = DateFormat('MMM d, y');
    final label = range.from == range.to
        ? fmt.format(range.from)
        : '${fmt.format(range.from)} – ${fmt.format(range.to)}';

    return RefreshIndicator(
      onRefresh: () async => invalidateBilling(ref),
      child: CenteredScroll(
        maxWidth: ContentWidth.detail,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        builder: (padding) => ListView(
          padding: padding,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _Period.values) ...[
                    ChoiceChip(
                      label: Text(switch (p) {
                        _Period.today => 'Today',
                        _Period.week => 'This week',
                        _Period.month => 'This month',
                        _Period.custom => 'Pick dates…',
                      }),
                      selected: _period == p,
                      onSelected: (_) => p == _Period.custom
                          ? _pickRange()
                          : setState(() => _period = p),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            AsyncView(
              value: summary,
              onRetry: () => ref.invalidate(ledgerSummaryProvider(range)),
              builder: (s) => s == null ? const SizedBox.shrink() : _Summary(s),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Money in and out',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Add expense'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AsyncView(
              value: entries,
              onRetry: () => ref.invalidate(ledgerEntriesProvider(range)),
              builder: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Nothing in these days.')),
                    )
                  : Column(
                      children: [
                        for (final e in list)
                          _EntryTile(
                            entry: e,
                            onTap: e.isExpense
                                ? () => _expenseMenu(e)
                                : e.invoiceId == null
                                    ? null
                                    : () => widget.onOpenInvoice(e.invoiceId!),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(clinicId: clinicId),
    );
    if (saved == true) invalidateBilling(ref);
  }

  /// An admin may void an expense; everyone else just sees it.
  Future<void> _expenseMenu(LedgerEntry e) async {
    final isAdmin = ref.read(currentClinicRoleProvider).value == AppRole.admin;
    if (!isAdmin || e.voided) return;
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidDialog(entry: e),
    );
    if (reason == null) return;
    try {
      await ref.read(healthRepositoryProvider).voidExpense(e.id, reason);
      messenger.showSnackBar(const SnackBar(
          content: Text('Expense voided'), behavior: SnackBarBehavior.floating));
    } catch (err) {
      messenger.showSnackBar(SnackBar(
          content: Text(describeError(err)), behavior: SnackBarBehavior.floating));
    } finally {
      invalidateBilling(ref);
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.s);

  final LedgerSummary s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    final tiles = [
      _Tile(
        label: 'Gross',
        value: s.gross,
        icon: Icons.receipt_long_outlined,
        accent: cs.primary,
        note: s.discounts > 0
            ? '${plural(s.billCount, 'bill')} · ${formatPeso(s.discounts)} off'
            : plural(s.billCount, 'bill'),
      ),
      _Tile(
        label: 'Paid',
        value: s.paid,
        icon: Icons.check_circle_outline,
        accent: InvoiceStatus.paid.color.readableIn(context),
        note: plural(s.paymentCount, 'payment'),
      ),
      _Tile(
        label: 'Pending',
        value: s.pending,
        icon: Icons.hourglass_bottom,
        accent: InvoiceStatus.issued.color.readableIn(context),
        note: 'on these days\' bills',
      ),
      _Tile(
        label: 'Expenses',
        value: s.expenses,
        icon: Icons.remove_circle_outline,
        accent: InvoiceStatus.voided.color.readableIn(context),
      ),
      _Tile(
        label: 'Net',
        value: s.net,
        icon: s.net >= 0 ? Icons.trending_up : Icons.trending_down,
        accent: s.net >= 0 ? InvoiceStatus.paid.color.readableIn(context) : InvoiceStatus.voided.color.readableIn(context),
        note: 'paid − expenses',
        emphasis: true,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth >= 720 ? 5 : (box.maxWidth >= 420 ? 3 : 2);
          const gap = 8.0;
          final w = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        }),
        const SizedBox(height: 8),
        if (s.outstanding > 0 || s.draftCount > 0)
          Text(
            [
              if (s.outstanding > 0)
                'Owed overall: ${formatPeso(s.outstanding)} on ${plural(s.unpaidCount, 'bill')}',
              if (s.draftCount > 0)
                '${plural(s.draftCount, 'draft')} not issued yet (${formatPeso(s.draftTotal)})',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        if (s.byMethod.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Breakdown(
            title: 'Paid by',
            rows: [
              for (final m in PaymentMethod.values)
                if (s.byMethod[m] case final v?) (m.displayName, v),
            ],
            color: InvoiceStatus.paid.color.readableIn(context),
          ),
        ],
        if (s.byCategory.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Breakdown(
            title: 'Spent on',
            rows: (s.byCategory.entries.map((e) => (e.key, e.value)).toList()
              ..sort((a, b) => b.$2.compareTo(a.$2))),
            color: InvoiceStatus.voided.color.readableIn(context),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.note,
    this.emphasis = false,
  });

  final String label;
  final double value;
  final IconData icon;

  /// Marks the tile; the figures themselves stay in text colours.
  final Color accent;
  final String? note;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasis ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatPeso(value),
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          ),
          if (note != null)
            Text(note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Each row's share of the total as a thin bar, one colour, the amount in
/// text beside it.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.rows, required this.color});

  final String title;
  final List<(String, double)> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = rows.fold<double>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final (name, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 96, child: Text(name, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: top == 0 ? 0 : value / top,
                        minHeight: 8,
                        color: color,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Text(formatPeso(value),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.onTap});

  final LedgerEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = entry;
    final strike = e.voided ? TextDecoration.lineThrough : null;
    final when = e.isExpense
        ? DateFormat('MMM d').format(e.at)
        : DateFormat('MMM d · h:mm a').format(e.at);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: cs.surfaceContainerHigh,
        child: Icon(
          e.isExpense ? Icons.arrow_upward : Icons.arrow_downward,
          color: e.voided
              ? cs.outline
              : (e.isExpense ? InvoiceStatus.voided.color.readableIn(context) : InvoiceStatus.paid.color.readableIn(context)),
          semanticLabel: e.isExpense ? 'Expense' : 'Payment',
        ),
      ),
      title: Text(
        e.title,
        style: TextStyle(decoration: strike),
      ),
      subtitle: Text(
        e.voided
            ? 'Void: ${e.voidReason ?? ''}'
            : [
                when,
                e.method.displayName,
                if (e.detail != null) e.detail!,
                if (e.reference != null) e.reference!,
              ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${e.isExpense ? '−' : '+'}${formatPeso(e.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: strike,
          color: e.voided ? cs.outline : cs.onSurface,
        ),
      ),
    );
  }
}

class _ExpenseDialog extends ConsumerStatefulWidget {
  const _ExpenseDialog({required this.clinicId});

  final String clinicId;

  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_amount.text.replaceAll(',', '').replaceAll('₱', '').trim());

  bool get _valid =>
      (_parsed ?? 0) > 0 && _category.text.trim().isNotEmpty && !_busy;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).addExpense(
            clinicId: widget.clinicId,
            spentOn: _day,
            category: _category.text.trim(),
            amount: _parsed!,
            method: _method,
            description: _description.text.trim(),
            reference: _method.wantsReference ? _reference.text.trim() : null,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Add expense'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₱ '),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Category'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in expenseCategories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category.text.trim() == c,
                      onSelected: (_) => setState(() => _category.text = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                    labelText: 'What for (optional)',
                    hintText: 'e.g. Gloves and masks, 5 boxes'),
              ),
              const SizedBox(height: 12),
              Text('Paid with', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              _MethodPicker(
                value: _method,
                onChanged: (m) => setState(() => _method = m),
              ),
              if (_method.wantsReference) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _reference,
                  decoration: const InputDecoration(labelText: 'Reference (optional)'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final today = DateUtils.dateOnly(DateTime.now());
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(today.year - 2),
                    lastDate: today,
                  );
                  if (picked != null) setState(() => _day = picked);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text('Spent on ${DateFormat('EEE, MMM d, y').format(_day)}'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: cs.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _valid ? _save : null, child: const Text('Add')),
      ],
    );
  }
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({required this.entry});

  final LedgerEntry entry;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Void ${formatPeso(widget.entry.amount)} ${widget.entry.title} expense?'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Why — e.g. entered twice'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Void expense'),
        ),
      ],
    );
  }
}

/// The common methods as chips, the rest behind "More".
class _MethodPicker extends StatefulWidget {
  const _MethodPicker({required this.value, required this.onChanged});

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  State<_MethodPicker> createState() => _MethodPickerState();
}

class _MethodPickerState extends State<_MethodPicker> {
  late bool _all = !PaymentMethod.common.contains(widget.value);

  @override
  Widget build(BuildContext context) {
    return PaymentMethodChips(
      value: widget.value,
      onChanged: widget.onChanged,
      showAll: _all,
      onShowAll: () => setState(() => _all = true),
    );
  }
}

/// Payment method chips: [PaymentMethod.common] first, the rest once
/// [showAll]. Shared by the payment and expense dialogs.
class PaymentMethodChips extends StatelessWidget {
  const PaymentMethodChips({
    super.key,
    required this.value,
    required this.onChanged,
    required this.showAll,
    required this.onShowAll,
  });

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final methods = showAll ? PaymentMethod.values : PaymentMethod.common;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in methods)
          ChoiceChip(
            avatar: Icon(m.icon, size: 16),
            label: Text(m.displayName),
            selected: m == value,
            onSelected: (_) => onChanged(m),
          ),
        if (!showAll)
          ActionChip(
            avatar: const Icon(Icons.expand_more, size: 16),
            label: const Text('More'),
            onPressed: onShowAll,
          ),
      ],
    );
  }
}
