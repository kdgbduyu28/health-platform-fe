import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_role.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/service.dart';
import '../providers/billing_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// One bill. The front desk and admins build it while it is a draft, issue
/// it, and take payments on it; an admin can void a payment. Everyone else —
/// doctors, and the patient it is for — reads it.
///
/// Every figure on it comes back from the database after each change: the
/// screen never adds anything up itself.
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invoiceProvider(invoiceId));
    final guard = asyncGuard(
      async,
      appBar: AppBar(title: const Text('Bill')),
      onRetry: () => ref.invalidate(invoiceProvider(invoiceId)),
    );
    if (guard != null) return guard;
    final v = async.requireValue;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill')),
        body: const Center(child: Text('Bill not found.')),
      );
    }

    final canBill = ref.watch(canBillProvider).value ?? false;
    final role = ref.watch(currentClinicRoleProvider).value;
    final isAdmin = role == AppRole.admin;
    final isPatient = ref.watch(appRoleProvider) == AppRole.patient;
    final editing = canBill && v.isDraft;
    final actions = _Actions(context, ref, v);

    return Scaffold(
      appBar: AppBar(
        title: Text(v.number ?? 'Draft bill'),
        actions: [
          if (canBill && (v.isDraft || v.status != InvoiceStatus.voided))
            PopupMenuButton<String>(
              onSelected: (a) => a == 'delete' ? actions.deleteDraft() : actions.voidBill(),
              itemBuilder: (_) => [
                if (v.isDraft)
                  const PopupMenuItem(value: 'delete', child: Text('Delete draft'))
                else
                  const PopupMenuItem(value: 'void', child: Text('Void bill')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => invalidateBilling(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(invoice: v, showPatient: !isPatient),
            const SizedBox(height: 16),
            _Lines(invoice: v, editing: editing, actions: actions),
            const SizedBox(height: 12),
            _Totals(invoice: v, editing: editing, actions: actions),
            if (v.notes != null || canBill) ...[
              const SizedBox(height: 12),
              _NotesCard(invoice: v, editable: canBill, actions: actions),
            ],
            if (v.payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Payments(invoice: v, canVoid: isAdmin, actions: actions),
            ],
            const SizedBox(height: 20),
            if (editing)
              FilledButton.icon(
                onPressed: v.items.isEmpty ? null : actions.issue,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Issue bill'),
              )
            else if (canBill && v.isOpen)
              FilledButton.icon(
                onPressed: actions.recordPayment,
                icon: const Icon(Icons.payments_outlined),
                label: Text('Record payment · ${formatPeso(v.balance)} due'),
              )
            else if (isPatient && v.isOpen)
              Text(
                'Please settle ${formatPeso(v.balance)} at the clinic\'s front desk.',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 16),
            Text(
              'This is a statement of account, not an official receipt.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.invoice, required this.showPatient});

  final Invoice invoice;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = invoice;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: cs.onPrimary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showPatient && v.patient != null ? v.patient!.name : v.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.onPrimary.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(v.status.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ),
            if (v.visitAt != null)
              Text(
                '${showPatient ? '${v.title} · ' : ''}'
                '${DateFormat('EEE, MMM d, y').format(v.visitAt!)}',
                style: TextStyle(color: cs.onPrimary.withAlpha(210), fontSize: 13),
              ),
            const SizedBox(height: 14),
            Text(formatPeso(v.isOpen ? v.balance : v.total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            Text(
              switch (v.status) {
                InvoiceStatus.issued when v.amountPaid > 0 =>
                  'still owed of ${formatPeso(v.total)}',
                InvoiceStatus.issued => 'due',
                InvoiceStatus.paid => 'paid in full',
                InvoiceStatus.draft => 'draft — not yet issued',
                InvoiceStatus.voided =>
                  'void${v.voidReason == null ? '' : ': ${v.voidReason}'}',
              },
              style: TextStyle(color: cs.onPrimary.withAlpha(210)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontSize: 12)),
              const Spacer(),
              if (action != null) action!,
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.invoice, required this.editing, required this.actions});

  final Invoice invoice;
  final bool editing;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      title: 'Items',
      action: editing
          ? TextButton.icon(
              onPressed: () => actions.editLine(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            )
          : null,
      children: [
        if (invoice.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing on this bill yet.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final item in invoice.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            onTap: editing ? () => actions.editLine(item) : null,
            title: Text(item.description),
            subtitle: item.quantity > 1
                ? Text('${item.quantity} × ${formatPeso(item.unitPrice)}')
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatPeso(item.amount),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (editing)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => actions.removeLine(item),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.invoice, required this.editing, required this.actions});

  final Invoice invoice;
  final bool editing;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final v = invoice;
    final cs = Theme.of(context).colorScheme;
    Widget row(String label, String value, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(color: color ?? cs.onSurfaceVariant)),
              ),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
            ],
          ),
        );

    return _Card(
      title: 'Total',
      action: editing
          ? TextButton.icon(
              onPressed: actions.editDiscount,
              icon: const Icon(Icons.percent, size: 18),
              label: Text(v.discountAmount > 0 ? 'Change discount' : 'Discount'),
            )
          : null,
      children: [
        const SizedBox(height: 4),
        row('Subtotal', formatPeso(v.subtotal)),
        if (v.discountAmount > 0)
          row('Discount${v.discountReason == null ? '' : ' (${v.discountReason})'}',
              '−${formatPeso(v.discountAmount)}'),
        const Divider(height: 16),
        row('Total', formatPeso(v.total), bold: true),
        if (v.amountPaid > 0) row('Paid', formatPeso(v.amountPaid)),
        if (v.isOpen)
          row('Balance', formatPeso(v.balance), bold: true, color: cs.error),
      ],
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.invoice, required this.editable, required this.actions});

  final Invoice invoice;
  final bool editable;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final notes = invoice.notes;
    return _Card(
      title: 'Note on the bill',
      action: editable
          ? TextButton(
              onPressed: actions.editNotes,
              child: Text(notes == null ? 'Add' : 'Edit'),
            )
          : null,
      children: [
        if (notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(notes),
          )
        else
          Text('The patient sees this note too.',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Payments extends StatelessWidget {
  const _Payments({required this.invoice, required this.canVoid, required this.actions});

  final Invoice invoice;
  final bool canVoid;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Card(
      title: 'Payments',
      children: [
        for (final p in invoice.payments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(p.method.icon,
                color: p.isVoid ? cs.outline : cs.primary),
            title: Text(
              '${p.method.displayName}${p.reference == null ? '' : ' · ${p.reference}'}',
              style: TextStyle(
                  decoration: p.isVoid ? TextDecoration.lineThrough : null),
            ),
            subtitle: Text(p.isVoid
                ? 'Void: ${p.voidReason ?? ''}'
                : DateFormat('MMM d, y · h:mm a').format(p.receivedAt)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatPeso(p.amount),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: p.isVoid ? TextDecoration.lineThrough : null,
                        color: p.isVoid ? cs.outline : null)),
                if (canVoid && !p.isVoid && invoice.status != InvoiceStatus.voided)
                  IconButton(
                    tooltip: 'Void payment',
                    icon: const Icon(Icons.undo, size: 18),
                    onPressed: () => actions.voidPayment(p),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Every change to the bill: ask, send, refetch, and say what went wrong in
/// the database's own words.
class _Actions {
  _Actions(this.context, this.ref, this.invoice);

  final BuildContext context;
  final WidgetRef ref;
  final Invoice invoice;

  Future<void> _run(Future<void> Function() change, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      if (done != null) {
        messenger.showSnackBar(
            SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(describeError(e)), behavior: SnackBarBehavior.floating));
    } finally {
      invalidateBilling(ref);
    }
  }

  Future<void> editLine(InvoiceItem? item) async {
    final services = ref.read(servicesProvider).value ?? const <Service>[];
    final line = await showDialog<_LineDraft>(
      context: context,
      builder: (_) => _LineDialog(item: item, services: services),
    );
    if (line == null) return;
    final repo = ref.read(healthRepositoryProvider);
    await _run(() => item == null
        ? repo.addInvoiceItem(
            invoiceId: invoice.id,
            clinicId: invoice.clinicId,
            description: line.description,
            unitPrice: line.unitPrice,
            quantity: line.quantity,
            serviceId: line.serviceId,
          )
        : repo.updateInvoiceItem(item.id,
            description: line.description,
            unitPrice: line.unitPrice,
            quantity: line.quantity));
  }

  Future<void> removeLine(InvoiceItem item) =>
      _run(() => ref.read(healthRepositoryProvider).deleteInvoiceItem(item.id));

  Future<void> editDiscount() async {
    final result = await showDialog<({double amount, String? reason})>(
      context: context,
      builder: (_) => _DiscountDialog(invoice: invoice),
    );
    if (result == null) return;
    await _run(() => ref.read(healthRepositoryProvider).setInvoiceDiscount(
        invoice.id,
        amount: result.amount,
        reason: result.reason));
  }

  Future<void> editNotes() async {
    final text = await _askText(context,
        title: 'Note on the bill',
        initial: invoice.notes,
        hint: 'e.g. HMO: Maxicare, LOA 12345',
        maxLines: 4,
        allowEmpty: true);
    if (text == null) return;
    await _run(() => ref.read(healthRepositoryProvider).setInvoiceNotes(invoice.id, text));
  }

  Future<void> issue() async {
    final ok = await _confirm(context,
        title: 'Issue this bill?',
        body: 'It gets a number and can no longer be edited. '
            '${invoice.patient?.name ?? 'The patient'} will see it in their app.',
        action: 'Issue');
    if (!ok) return;
    await _run(() => ref.read(healthRepositoryProvider).issueInvoice(invoice.id),
        done: 'Bill issued');
  }

  Future<void> recordPayment() async {
    final result = await showDialog<_PaymentDraft>(
      context: context,
      builder: (_) => _PaymentDialog(balance: invoice.balance),
    );
    if (result == null) return;
    await _run(
      () => ref.read(healthRepositoryProvider).recordPayment(
            invoiceId: invoice.id,
            clinicId: invoice.clinicId,
            amount: result.amount,
            method: result.method,
            reference: result.reference,
          ),
      done: result.amount >= invoice.balance
          ? 'Paid in full'
          : '${formatPeso(result.amount)} received',
    );
  }

  Future<void> voidPayment(Payment p) async {
    final reason = await _askText(context,
        title: 'Void ${formatPeso(p.amount)} ${p.method.displayName} payment?',
        hint: 'Why — e.g. wrong amount, refunded',
        action: 'Void payment');
    if (reason == null) return;
    await _run(() => ref.read(healthRepositoryProvider).voidPayment(p.id, reason),
        done: 'Payment voided');
  }

  Future<void> voidBill() async {
    final reason = await _askText(context,
        title: 'Void ${invoice.label}?',
        hint: 'Why — e.g. billed the wrong patient',
        action: 'Void bill');
    if (reason == null) return;
    await _run(() => ref.read(healthRepositoryProvider).voidInvoice(invoice.id, reason),
        done: 'Bill voided');
  }

  Future<void> deleteDraft() async {
    final ok = await _confirm(context,
        title: 'Delete this draft?', body: 'It was never issued.', action: 'Delete');
    if (!ok || !context.mounted) return;
    final navigator = Navigator.of(context);
    await _run(() => ref.read(healthRepositoryProvider).deleteInvoice(invoice.id));
    if (navigator.canPop()) navigator.pop();
  }
}

Future<bool> _confirm(BuildContext context,
    {required String title, required String body, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

/// Asks for one line of text. Null if cancelled; with [allowEmpty], an empty
/// string means "clear it".
Future<String?> _askText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String action = 'Save',
  int maxLines = 1,
  bool allowEmpty = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: title,
        initial: initial,
        hint: hint,
        action: action,
        maxLines: maxLines,
        allowEmpty: allowEmpty,
      ),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.action,
    required this.maxLines,
    required this.allowEmpty,
  });

  final String title;
  final String? initial;
  final String? hint;
  final String action;
  final int maxLines;
  final bool allowEmpty;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLines: widget.maxLines,
        decoration: InputDecoration(hintText: widget.hint),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: widget.allowEmpty || _text.text.trim().isNotEmpty
              ? () => Navigator.pop(context, _text.text.trim())
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

double? _parseAmount(String text) =>
    double.tryParse(text.replaceAll(',', '').replaceAll('₱', '').trim());

final _amountInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

typedef _LineDraft = ({
  String description,
  double unitPrice,
  int quantity,
  String? serviceId,
});

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.item, required this.services});

  final InvoiceItem? item;
  final List<Service> services;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final _description = TextEditingController(text: widget.item?.description);
  late final _price = TextEditingController(
      text: widget.item == null ? '' : widget.item!.unitPrice.toStringAsFixed(2));
  late final _quantity =
      TextEditingController(text: '${widget.item?.quantity ?? 1}');
  String? _serviceId;

  @override
  void dispose() {
    _description.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = _parseAmount(_price.text);
    final quantity = int.tryParse(_quantity.text);
    final valid = _description.text.trim().isNotEmpty &&
        price != null &&
        price >= 0 &&
        quantity != null &&
        quantity >= 1 &&
        quantity <= 999;

    return AlertDialog(
      title: Text(widget.item == null ? 'Add item' : 'Edit item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.item == null && widget.services.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in widget.services)
                    ActionChip(
                      label: Text(s.priceLabel == null ? s.name : '${s.name} · ${s.priceLabel}'),
                      onPressed: () => setState(() {
                        _serviceId = s.id;
                        _description.text = s.name;
                        _price.text = (s.price ?? 0).toStringAsFixed(2);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _description,
              autofocus: widget.item != null,
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (_) => setState(() => _serviceId = null),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _amountInput,
                    decoration: const InputDecoration(labelText: 'Price', prefixText: '₱ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop<_LineDraft>(context, (
                    description: _description.text.trim(),
                    unitPrice: price,
                    quantity: quantity,
                    serviceId: _serviceId,
                  ))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.invoice});

  final Invoice invoice;

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late final _amount = TextEditingController(
      text: widget.invoice.discountAmount > 0
          ? widget.invoice.discountAmount.toStringAsFixed(2)
          : '');
  late final _reason = TextEditingController(text: widget.invoice.discountReason);

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _twentyPercent(String reason) => setState(() {
        final twenty = (widget.invoice.subtotal * 0.2 * 100).round() / 100;
        _amount.text = twenty.toStringAsFixed(2);
        _reason.text = reason;
      });

  @override
  Widget build(BuildContext context) {
    final amount = _amount.text.trim().isEmpty ? 0.0 : _parseAmount(_amount.text);
    final valid = amount != null && amount >= 0 && amount <= widget.invoice.subtotal;
    return AlertDialog(
      title: const Text('Discount'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              ActionChip(
                  label: const Text('Senior citizen 20%'),
                  onPressed: () => _twentyPercent('Senior citizen')),
              ActionChip(label: const Text('PWD 20%'), onPressed: () => _twentyPercent('PWD')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _amountInput,
            decoration: InputDecoration(
              labelText: 'Amount off',
              prefixText: '₱ ',
              helperText: 'Of ${formatPeso(widget.invoice.subtotal)}. Empty or 0 removes it.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason (shown on the bill)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop<({double amount, String? reason})>(
                  context, (amount: amount, reason: _reason.text.trim()))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

typedef _PaymentDraft = ({double amount, PaymentMethod method, String? reference});

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.balance});

  final double balance;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.balance.toStringAsFixed(2));
  final _reference = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parseAmount(_amount.text);
    final valid = amount != null && amount > 0 && amount <= widget.balance + 0.001;
    return AlertDialog(
      title: const Text('Record payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    avatar: Icon(m.icon, size: 16),
                    label: Text(m.displayName),
                    selected: m == _method,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _amountInput,
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₱ ',
                helperText: '${formatPeso(widget.balance)} due',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_method.wantsReference) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reference,
                decoration: InputDecoration(
                  labelText: switch (_method) {
                    PaymentMethod.hmo => 'Approval / LOA code',
                    PaymentMethod.card => 'Approval code',
                    _ => 'Reference number',
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop<_PaymentDraft>(context, (
                    amount: amount,
                    method: _method,
                    reference: _method.wantsReference ? _reference.text.trim() : null,
                  ))
              : null,
          child: const Text('Record'),
        ),
      ],
    );
  }
}
