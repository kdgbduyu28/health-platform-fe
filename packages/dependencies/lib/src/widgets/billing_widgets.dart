import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/appointment.dart';
import '../models/appointment_status.dart';
import '../models/invoice.dart';
import '../models/money.dart';
import '../providers/billing_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

class InvoiceStatusChip extends StatelessWidget {
  const InvoiceStatusChip({super.key, required this.status});

  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withAlpha(80)),
      ),
      child: Text(status.displayName,
          style: TextStyle(
              color: status.color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// One bill in a list: what it is for, when, how much, and what is left.
class InvoiceTile extends StatelessWidget {
  const InvoiceTile({
    super.key,
    required this.invoice,
    required this.onTap,
    this.showPatient = false,
  });

  final Invoice invoice;
  final VoidCallback onTap;
  final bool showPatient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = invoice;
    final when = v.visitAt ?? v.issuedAt ?? v.createdAt;
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        title: Text(
          showPatient && v.patient != null ? v.patient!.name : v.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text([
          if (showPatient && v.patient != null) v.title,
          v.label,
          DateFormat('MMM d, y').format(when),
        ].join(' · ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPeso(v.total),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (v.isOpen && v.amountPaid > 0)
              Text('${formatPeso(v.balance)} left',
                  style: TextStyle(fontSize: 12, color: cs.error))
            else
              InvoiceStatusChip(status: v.status),
          ],
        ),
      ),
    );
  }
}

/// The bill for one visit, on an appointment screen: its state, or — for the
/// front desk and admins once the patient is in — a button to start one.
class VisitBillSection extends ConsumerWidget {
  const VisitBillSection({
    super.key,
    required this.appointment,
    required this.onOpenInvoice,
  });

  final Appointment appointment;
  final void Function(String invoiceId) onOpenInvoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final canBill = ref.watch(canBillProvider).value ?? false;
    final billAsync = ref.watch(appointmentInvoiceProvider(appointment.id));
    final billable = switch (appointment.status) {
      AppointmentStatus.arrived ||
      AppointmentStatus.inConsultation ||
      AppointmentStatus.completed =>
        true,
      _ => false,
    };

    final bill = billAsync.value;
    if (bill == null && !(canBill && billable)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text('Bill',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            if (billAsync.isLoading && bill == null)
              const LinearProgressIndicator()
            else if (bill != null)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpenInvoice(bill.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatPeso(bill.total),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(
                            bill.isOpen && bill.amountPaid > 0
                                ? '${bill.label} · ${formatPeso(bill.balance)} still owed'
                                : bill.label,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    InvoiceStatusChip(status: bill.status),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              )
            else
              FilledButton.tonalIcon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final id = await ref
                        .read(healthRepositoryProvider)
                        .createInvoiceForAppointment(appointment.id);
                    invalidateBilling(ref);
                    onOpenInvoice(id);
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                      content: Text(describeError(e)),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Create bill'),
              ),
          ],
        ),
      ),
    );
  }
}
