import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:api_sdk/api_sdk.dart';

class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key});

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final todayAsync = ref.watch(todayAppointmentsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Header stats need numbers before the list renders; empty is the honest
    // stand-in while loading, and the list below still reports real errors.
    final todayAppts = todayAsync.value ?? const <Appointment>[];

    final filtered = todayAppts.where((a) {
      if (_query.isEmpty) return true;
      return a.patient.name.toLowerCase().contains(_query.toLowerCase()) ||
          a.patient.phone.contains(_query);
    }).toList();

    int count(AppointmentStatus s) =>
        todayAppts.where((a) => a.status == s).length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                ClinicTitle(
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: const [AccountMenuButton(), SizedBox(width: 8)],
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      for (final (i, (label, status)) in const [
                        ('To confirm', AppointmentStatus.pending),
                        ('Expected', AppointmentStatus.confirmed),
                        ('Waiting', AppointmentStatus.arrived),
                        ('Seen', AppointmentStatus.completed),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        _StatPill(
                            label: label,
                            value: count(status),
                            color: status.color),
                      ],
                    ],
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search patient by name or phone…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _query = ''),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // "No appointments today" is only true once the data has actually
          // arrived — while loading or after a failure it would be a lie.
          if (!todayAsync.hasValue)
            SliverFillRemaining(
              child: AsyncView(
                value: todayAsync,
                onRetry: () => ref.invalidate(appointmentsProvider),
                builder: (_) => const SizedBox.shrink(),
              ),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available,
                        size: 56, color: cs.outline),
                    const SizedBox(height: 12),
                    Text(
                      _query.isNotEmpty
                          ? 'No results for "$_query"'
                          : 'No appointments today',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final a = filtered[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: _CheckInCard(appointment: a),
                );
              },
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: color)),
            Text(label,
                style: TextStyle(fontSize: 11, color: color),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CheckInCard extends ConsumerWidget {
  const _CheckInCard({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final timeStr = DateFormat('h:mm a').format(appointment.dateTime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(appointment.patient.initials,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appointment.patient.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(appointment.patient.phone,
                          style:
                              TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                StatusBadge(status: appointment.status, small: true),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time_outlined,
                    size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(timeStr,
                    style: TextStyle(color: cs.primary, fontSize: 13)),
                const SizedBox(width: 12),
                Icon(Icons.medical_services_outlined,
                    size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(appointment.service,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            ..._actions(context, ref, cs),
          ],
        ),
      ),
    );
  }

  /// What the front desk can do next with this visit.
  List<Widget> _actions(BuildContext context, WidgetRef ref, ColorScheme cs) {
    final a = appointment;
    final since = switch (a.status) {
      AppointmentStatus.arrived when a.arrivedAt != null =>
        'Waiting since ${DateFormat.jm().format(a.arrivedAt!)}',
      AppointmentStatus.inConsultation when a.startedAt != null =>
        'With the doctor since ${DateFormat.jm().format(a.startedAt!)}',
      _ => null,
    };
    final buttons = <Widget>[
      if (a.status == AppointmentStatus.pending)
        _Primary(
          icon: Icons.check,
          label: 'Confirm',
          onPressed: () => changeAppointmentStatus(
              context, ref, a, AppointmentStatus.confirmed,
              done: 'Appointment confirmed'),
        ),
      if (a.status == AppointmentStatus.confirmed)
        _Primary(
          icon: Icons.how_to_reg,
          label: 'Check in',
          onPressed: () => changeAppointmentStatus(
              context, ref, a, AppointmentStatus.arrived,
              done: '${a.patient.name} is in the waiting room'),
        ),
      // Only once the time has come: the database refuses it earlier.
      if (a.status == AppointmentStatus.confirmed &&
          !a.dateTime.isAfter(DateTime.now()))
        TextButton(
          onPressed: () => changeAppointmentStatus(
              context, ref, a, AppointmentStatus.noShow,
              done: 'Marked as a no-show'),
          child: const Text('No-show'),
        ),
      if (a.status.staffCanCancel)
        OutlinedButton(
          onPressed: () => confirmAndCancelAppointment(context, ref, a,
              who: a.patient.name),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.error,
            side: BorderSide(color: cs.error),
            minimumSize: const Size(0, 36),
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: const Text('Cancel'),
        ),
    ];
    return [
      if (since != null) ...[
        const SizedBox(height: 8),
        Text(since,
            style: TextStyle(
                color: a.status.color,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
      if (buttons.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ],
    ];
  }
}

class _Primary extends StatelessWidget {
  const _Primary({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}
