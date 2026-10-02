import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/adaptive_layout.dart';
import '../models/audit_entry.dart';
import '../providers/audit_provider.dart';
import '../providers/clinic_provider.dart';
import 'async_view.dart';

/// The clinic's activity log: who changed what, and when. Admins only.
///
/// A page of its own in the admin app, with a filter by area. The patient
/// page shows the same list for one chart ([AuditLogView] with a
/// `patientId`).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key, this.onOpenPatient});

  final void Function(String patientId)? onOpenPatient;

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  AuditArea? _area;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: Column(
        children: [
          Centered(
            maxWidth: ContentWidth.list + 32,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  for (final a in [null, ...AuditArea.values])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(a?.label ?? 'Everything'),
                        selected: _area == a,
                        onSelected: (_) => setState(() => _area = a),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: AuditLogView(
              key: ValueKey(_area),
              area: _area,
              onOpenPatient: widget.onOpenPatient,
            ),
          ),
        ],
      ),
    );
  }
}

/// The log as a list, newest first, grouped by day, loading older entries as
/// it is scrolled. With [patientId], only the changes to that chart.
class AuditLogView extends ConsumerStatefulWidget {
  const AuditLogView({
    super.key,
    this.patientId,
    this.area,
    this.onOpenPatient,
  });

  final String? patientId;
  final AuditArea? area;
  final void Function(String patientId)? onOpenPatient;

  @override
  ConsumerState<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends ConsumerState<AuditLogView> {
  final _entries = <AuditEntry>[];
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    final clinicId = ref.read(currentClinicIdProvider);
    if (clinicId == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries.clear();
        _hasMore = true;
      }
    });
    try {
      final page = await ref.read(auditRepositoryProvider).fetch(
            clinicId: clinicId,
            patientId: widget.patientId,
            area: widget.area,
            beforeId: _entries.isEmpty ? null : _entries.last.id,
          );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_entries.isEmpty) {
      if (_error != null) {
        return _Message(
          icon: Icons.error_outline,
          text: describeError(_error!),
          action: TextButton(onPressed: _load, child: const Text('Retry')),
        );
      }
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _Message(
        icon: Icons.history,
        text: widget.patientId == null
            ? 'No changes recorded yet.'
            : 'No changes to this patient recorded yet.',
      );
    }

    // Day headers between the entries.
    final items = <Object>[];
    DateTime? day;
    for (final e in _entries) {
      final d = DateUtils.dateOnly(e.createdAt);
      if (d != day) items.add(d);
      day = d;
      items.add(e);
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_hasMore &&
              !_loading &&
              _error == null &&
              n.metrics.extentAfter < 400) {
            _load();
          }
          return false;
        },
        child: CenteredScroll(
          maxWidth: ContentWidth.list,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          builder: (padding) => ListView.builder(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == items.length) {
                if (_error != null) {
                  return Center(
                    child: TextButton(
                        onPressed: _load, child: const Text('Retry')),
                  );
                }
                return _hasMore
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text('That is everything.',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ),
                      );
              }
              final item = items[i];
              if (item is DateTime) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                  child: Text(
                    _dayLabel(item),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                );
              }
              final e = item as AuditEntry;
              return _EntryTile(
                entry: e,
                showPatient: widget.patientId == null,
                onTap: () => showAuditEntrySheet(context, e,
                    onOpenPatient: widget.patientId == null
                        ? widget.onOpenPatient
                        : null),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat(d.year == today.year ? 'EEEE, d MMMM' : 'EEEE, d MMMM y')
        .format(d);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

IconData _icon(AuditEntry e) => switch (e.action) {
      AuditAction.insert => Icons.add_circle_outline,
      AuditAction.delete => Icons.remove_circle_outline,
      AuditAction.update => switch (e.area) {
          AuditArea.patients => Icons.person_outline,
          AuditArea.visits => Icons.event_outlined,
          AuditArea.billing => Icons.receipt_long_outlined,
          _ => Icons.edit_outlined,
        },
    };

String _byLine(AuditEntry e) {
  final role = e.actorRoleLabel;
  return role == null ? e.actorLabel : '${e.actorLabel} ($role)';
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.showPatient,
    required this.onTap,
  });

  final AuditEntry entry;
  final bool showPatient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final e = entry;
    final preview = e.action == AuditAction.update
        ? e.changes
            .take(2)
            .map((c) => c.before == null
                ? '${c.label} ${c.after}'
                : '${c.label}: ${c.before} → ${c.after}')
            .join(' · ')
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        leading: Icon(_icon(e),
            color: e.action == AuditAction.delete ? cs.error : cs.primary),
        title: Text.rich(TextSpan(children: [
          TextSpan(
              text: e.headline,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (showPatient && e.patientName != null)
            TextSpan(text: ' · ${e.patientName}'),
        ])),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null && preview.isNotEmpty)
              Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              '${_byLine(e)} · ${DateFormat.jm().format(e.createdAt)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Everything one entry recorded: every field, before and after.
Future<void> showAuditEntrySheet(
  BuildContext context,
  AuditEntry entry, {
  void Function(String patientId)? onOpenPatient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: ContentWidth.form),
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final e = entry;
      final changes = e.changes;
      final patientId = e.patientId;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(e.headline,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (e.patientName != null) ...[
              const SizedBox(height: 2),
              Text(e.patientName!, style: theme.textTheme.titleMedium),
            ],
            const SizedBox(height: 8),
            Text(
              '${_byLine(e)}\n'
              '${DateFormat('EEEE, d MMMM y · h:mm:ss a').format(e.createdAt)}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (changes.isEmpty)
              Text('No details were recorded.',
                  style: TextStyle(color: cs.onSurfaceVariant))
            else
              for (final c in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      if (c.before != null && c.after != null) ...[
                        Text(c.before!,
                            style: TextStyle(
                                color: cs.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough)),
                        Text(c.after!),
                      ] else
                        Text(c.after ?? c.before!,
                            style: e.action == AuditAction.delete
                                ? TextStyle(color: cs.onSurfaceVariant)
                                : null),
                    ],
                  ),
                ),
            if (onOpenPatient != null && patientId != null && e.action != AuditAction.delete)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onOpenPatient(patientId);
                  },
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Open patient'),
                ),
              ),
          ],
        ),
      );
    },
  );
}
