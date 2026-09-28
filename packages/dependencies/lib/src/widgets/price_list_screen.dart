import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/adaptive_layout.dart';
import '../models/service.dart';
import '../providers/catalog_provider.dart';
import '../providers/supabase_providers.dart';
import 'async_view.dart';

/// What each service costs, for the front desk and admins. Marking a visit
/// done puts its services on the bill at these prices.
///
/// Prices only: adding, renaming and retiring services stays in the admin
/// app's Clinic › Services. A new price applies to bills drafted from now
/// on; lines already on a bill keep theirs.
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key});

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prices')),
      body: AsyncView(
        value: ref.watch(catalogueProvider),
        onRetry: () => ref.invalidate(catalogueProvider),
        builder: (all) {
          final active = [for (final s in all) if (s.isActive) s];
          final q = _query.toLowerCase();
          final shown = [
            for (final s in active)
              if (q.isEmpty || s.name.toLowerCase().contains(q)) s,
          ];
          final unpriced = active.where((s) => s.price == null).length;
          if (active.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No services yet. An admin adds them under '
                    'Clinic › Services.', textAlign: TextAlign.center),
              ),
            );
          }
          return CenteredScroll(
            maxWidth: ContentWidth.list,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            builder: (padding) => ListView(
              padding: padding,
              children: [
                if (unpriced > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '$unpriced ${unpriced == 1 ? 'service has' : 'services have'} '
                      'no price yet. They go on bills at ₱0 until one is set.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (active.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: const InputDecoration(
                        hintText: 'Find a service…',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                for (final s in shown)
                  Card(
                    child: ListTile(
                      onTap: () => _edit(s),
                      leading: const Icon(Icons.sell_outlined),
                      title: Text(s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${s.durationMinutes} min'),
                      trailing: Text(
                        s.priceLabel ?? 'Set price',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: s.price == null
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(Service s) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PriceDialog(service: s),
    );
    if (saved == true) invalidateCatalog(ref);
  }
}

class _PriceDialog extends ConsumerStatefulWidget {
  const _PriceDialog({required this.service});

  final Service service;

  @override
  ConsumerState<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends ConsumerState<_PriceDialog> {
  late final _price = TextEditingController(
    text: switch (widget.service.price) {
      null => '',
      final p when p == p.roundToDouble() => p.toStringAsFixed(0),
      final p => p.toStringAsFixed(2),
    },
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  double? get _parsed => double.tryParse(_price.text.replaceAll(',', '').trim());

  bool get _valid =>
      _price.text.trim().isEmpty || (_parsed != null && _parsed! >= 0);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).setServicePrice(
          widget.service.id, _price.text.trim().isEmpty ? null : _parsed);
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
    return AlertDialog(
      title: Text(widget.service.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(
              labelText: 'Price',
              prefixText: '₱ ',
              helperText: 'Empty clears it. Bills already drafted keep '
                  'their price.',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _valid && !_busy ? _save() : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid && !_busy ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
