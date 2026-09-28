import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../models/service.dart';
import '../providers/appointments_provider.dart';
import '../providers/billing_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// Marks [appointment] done: asks which services were performed, shows what
/// they come to at the clinic's prices, and saves both — the visit completed,
/// the services on its bill. Anyone on staff may.
///
/// Returns the visit's bill id when it has one, '' when saved without a bill
/// (no services ticked), or null if cancelled or refused. The refusal is
/// shown as a snackbar in the database's words.
///
/// On a visit already completed it corrects the services instead.
Future<String?> showCompleteVisitSheet(
  BuildContext context,
  WidgetRef ref,
  Appointment appointment,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CompleteVisitSheet(appointment: appointment),
  );
  if (result == null) return null;
  messenger?.showSnackBar(SnackBar(
    content: Text(appointment.status == AppointmentStatus.completed
        ? 'Services updated'
        : 'Visit done'),
    behavior: SnackBarBehavior.floating,
  ));
  return result;
}

class _CompleteVisitSheet extends ConsumerStatefulWidget {
  const _CompleteVisitSheet({required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<_CompleteVisitSheet> createState() => _CompleteVisitSheetState();
}

class _CompleteVisitSheetState extends ConsumerState<_CompleteVisitSheet> {
  /// Service id → how many times. Null until prefilled from the bill (or
  /// the booked service), so the prefill happens once.
  Map<String, int>? _picked;
  String _query = '';
  bool _busy = false;
  String? _error;

  Map<String, int> _prefill(Invoice? bill) {
    final fromBill = <String, int>{
      for (final i in bill?.items ?? const <InvoiceItem>[])
        if (i.serviceId != null) i.serviceId!: i.quantity,
    };
    if (fromBill.isNotEmpty) return fromBill;
    final booked = widget.appointment.serviceId;
    return {if (booked != null) booked: 1};
  }

  Future<void> _save() async {
    final picked = _picked ?? const {};
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(healthRepositoryProvider)
          .completeVisit(widget.appointment.id, services: picked);
      invalidateBilling(ref);
      await ref.read(appointmentsProvider.notifier).refresh();
      if (mounted) Navigator.pop(context, id ?? '');
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = widget.appointment;
    final billAsync = ref.watch(appointmentInvoiceProvider(a.id));
    final servicesAsync = ref.watch(catalogueProvider);
    final correcting = a.status == AppointmentStatus.completed;

    // Wait for the bill before prefilling from it.
    if (_picked == null && billAsync.hasValue) {
      _picked = _prefill(billAsync.value);
    }
    final bill = billAsync.value;
    final locked = bill != null && !bill.isDraft;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(correcting ? 'Services done' : 'Mark visit done',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${a.patient.name} · booked for ${a.service}',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (locked)
            Text(
              'This visit\'s bill (${bill.label}) has been issued, so the '
              'services on it no longer change here. '
              '${correcting ? '' : 'The visit will still be marked done.'}',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
          else
            Flexible(
              child: AsyncView(
                value: servicesAsync,
                onRetry: () => ref.invalidate(catalogueProvider),
                builder: (all) => _picker(context, all),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || _picked == null || (correcting && locked)
                ? null
                : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.task_alt),
            label: Text(_buttonLabel(servicesAsync.value, correcting, locked)),
          ),
        ],
      ),
    );
  }

  String _buttonLabel(List<Service>? all, bool correcting, bool locked) {
    final verb = correcting ? 'Save' : 'Mark done';
    if (locked || all == null) return verb;
    final total = _total(all);
    return total > 0 ? '$verb · ${formatPeso(total)}' : verb;
  }

  double _total(List<Service> all) {
    final picked = _picked ?? const {};
    return all.fold(
        0, (sum, s) => sum + (s.price ?? 0) * (picked[s.id] ?? 0));
  }

  Widget _picker(BuildContext context, List<Service> all) {
    final cs = Theme.of(context).colorScheme;
    final picked = _picked ?? const <String, int>{};
    // Retired services only when already on this visit.
    final offered = [
      for (final s in all)
        if (s.isActive || picked.containsKey(s.id)) s,
    ];
    final q = _query.toLowerCase();
    final shown = [
      for (final s in offered)
        if (q.isEmpty || s.name.toLowerCase().contains(q) || picked.containsKey(s.id)) s,
    ];
    final unpriced = [
      for (final s in offered)
        if (picked.containsKey(s.id) && s.price == null) s.name,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offered.length > 8) ...[
          TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Find a service…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in shown)
                _ServiceRow(
                  service: s,
                  quantity: picked[s.id] ?? 0,
                  onChanged: (n) => setState(() {
                    final next = {...picked};
                    if (n <= 0) {
                      next.remove(s.id);
                    } else {
                      next[s.id] = n.clamp(1, 999);
                    }
                    _picked = next;
                  }),
                ),
            ],
          ),
        ),
        const Divider(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('Total',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            Text(formatPeso(_total(all)),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        if (unpriced.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No price set for ${unpriced.join(', ')} — it goes on the bill '
              'at ₱0. Set prices under Billing › Prices.',
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
        if (picked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Nothing ticked: the visit is marked done without a bill.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.quantity,
    required this.onChanged,
  });

  final Service service;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = quantity > 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () => onChanged(on ? 0 : 1),
      leading: Checkbox(value: on, onChanged: (v) => onChanged(v! ? 1 : 0)),
      title: Text(service.name),
      subtitle: Text(service.priceLabel ?? 'No price set',
          style: TextStyle(color: service.price == null ? cs.error : null)),
      trailing: on
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'One fewer',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onChanged(quantity - 1),
                ),
                Text('$quantity',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'One more',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: quantity >= 999 ? null : () => onChanged(quantity + 1),
                ),
              ],
            )
          : null,
    );
  }
}
