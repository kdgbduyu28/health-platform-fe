import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_sdk/api_sdk.dart';

/// `/:clinic/settings/services` — what patients can book, how long each
/// takes, and what it costs.
///
/// The duration is what a booking blocks on the doctor's calendar, so it
/// decides which times `available_slots` offers. Services are retired, not
/// deleted: past visits point at them.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: AsyncView(
        value: catalogue,
        onRetry: () => ref.invalidate(catalogueProvider),
        builder: (services) => services.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No services yet. Add what patients can book.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final s = services[i];
                  final cs = Theme.of(context).colorScheme;
                  return Card(
                    child: ListTile(
                      onTap: () => _edit(context, ref, s),
                      leading: Icon(Icons.medical_services_outlined,
                          color: s.isActive ? cs.primary : cs.outline),
                      title: Text(s.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: s.isActive ? null : cs.outline,
                          )),
                      subtitle: Text([
                        '${s.durationMinutes} min',
                        s.priceLabel ?? 'No price set',
                      ].join(' · ')),
                      trailing: s.isActive
                          ? const Icon(Icons.edit_outlined)
                          : const Chip(label: Text('Retired')),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Service? service) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ServiceEditor(service: service),
    );
    if (saved == true) invalidateCatalog(ref);
  }
}

class _ServiceEditor extends ConsumerStatefulWidget {
  const _ServiceEditor({this.service});

  final Service? service;

  @override
  ConsumerState<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends ConsumerState<_ServiceEditor> {
  static const _durations = [10, 15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240];

  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _price = TextEditingController(
    text: switch (widget.service?.price) {
      null => '',
      final p when p == p.roundToDouble() => p.toStringAsFixed(0),
      final p => p.toStringAsFixed(2),
    },
  );
  late int _minutes = widget.service?.durationMinutes ?? 30;
  late bool _active = widget.service?.isActive ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final priceText = _price.text.trim().replaceAll(',', '');
    final price = priceText.isEmpty ? null : double.parse(priceText);
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(healthRepositoryProvider);
    try {
      final service = widget.service;
      if (service == null) {
        await repo.addService(
          clinicId: ref.read(currentClinicIdProvider)!,
          name: _name.text.trim(),
          durationMinutes: _minutes,
          price: price,
        );
      } else {
        await repo.updateService(service.id, {
          'name': _name.text.trim(),
          'duration_minutes': _minutes,
          'price': price,
          'is_active': _active,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final message = describeError(e);
      if (mounted) {
        setState(() => _error = message.contains('services_clinic_id_name_key')
            ? 'There is already a service with that name.'
            : message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.service == null;
    final durations = {..._durations, _minutes}.toList()..sort();

    return AlertDialog(
      title: Text(isNew ? 'Add service' : 'Edit service'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _minutes,
                  decoration: const InputDecoration(
                    labelText: 'Takes',
                    helperText: 'How long it blocks the doctor\'s calendar.',
                  ),
                  items: [
                    for (final m in durations)
                      DropdownMenuItem(value: m, child: Text('$m minutes')),
                  ],
                  onChanged: (m) => setState(() => _minutes = m!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (optional)',
                    prefixText: '₱ ',
                    helperText: 'Shown to patients when they book.',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim().replaceAll(',', '');
                    if (t.isEmpty) return null;
                    final p = double.tryParse(t);
                    return (p == null || p < 0) ? 'Enter an amount, or leave it blank' : null;
                  },
                ),
                if (!isNew) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bookable'),
                    subtitle: const Text(
                        'Off retires it: no new bookings. Past and booked '
                        'visits keep it.'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                  if (widget.service!.durationMinutes != _minutes)
                    Text(
                      'A new length applies to new bookings. Visits already '
                      'booked keep the time they were booked for.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _save,
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
