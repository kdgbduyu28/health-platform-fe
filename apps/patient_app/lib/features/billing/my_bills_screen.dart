import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';

/// The signed-in patient's bills at this clinic, newest first, with what is
/// still owed on top. Paying happens at the clinic; this is the record.
class MyBillsScreen extends ConsumerWidget {
  const MyBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myInvoicesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bills & payments')),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(myInvoicesProvider),
        builder: (bills) {
          if (bills.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 56, color: cs.outline),
                  const SizedBox(height: 12),
                  Text('No bills yet',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }
          final owed = bills
              .where((b) => b.isOpen)
              .fold<double>(0, (sum, b) => sum + b.balance);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myInvoicesProvider),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (owed > 0)
                  Card(
                    color: cs.errorContainer,
                    child: ListTile(
                      leading: Icon(Icons.info_outline, color: cs.onErrorContainer),
                      title: Text('${formatPeso(owed)} to settle',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.onErrorContainer)),
                      subtitle: Text('Pay at the clinic\'s front desk.',
                          style: TextStyle(color: cs.onErrorContainer)),
                    ),
                  ),
                for (final b in bills)
                  InvoiceTile(
                    invoice: b,
                    onTap: () => context.pushInClinic('/bills/${b.id}'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
