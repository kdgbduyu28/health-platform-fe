import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_sdk/api_sdk.dart';

class MyAppointmentsScreen extends ConsumerStatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  ConsumerState<MyAppointmentsScreen> createState() =>
      _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState
    extends ConsumerState<MyAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(myAppointmentsProvider);
    final now = DateTime.now();

    // Tab labels carry counts, so they can only be built once the data is in.
    final all = allAsync.value ?? const <Appointment>[];
    final upcoming = all
        .where((a) =>
            a.dateTime.isAfter(now) &&
            a.status != AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final past = all
        .where((a) =>
            !a.dateTime.isAfter(now) ||
            a.status == AppointmentStatus.cancelled)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Upcoming (${upcoming.length})'),
            Tab(text: 'Past (${past.length})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/appointments/book'),
        icon: const Icon(Icons.add),
        label: const Text('Book'),
      ),
      body: AsyncView(
        value: allAsync,
        onRetry: () => ref.invalidate(appointmentsProvider),
        builder: (_) => RefreshIndicator(
          onRefresh: () =>
              ref.read(appointmentsProvider.notifier).refresh(),
          child: TabBarView(
            controller: _tabs,
            children: [
              _AppointmentList(
                appointments: upcoming,
                emptyMessage: 'No upcoming appointments',
                emptySubtitle: 'Tap + to book one',
              ),
              _AppointmentList(
                appointments: past,
                emptyMessage: 'No past appointments',
                emptySubtitle: 'Your appointment history will appear here',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.appointments,
    required this.emptyMessage,
    required this.emptySubtitle,
  });

  final List<Appointment> appointments;
  final String emptyMessage;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(emptyMessage,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(emptySubtitle,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final a = appointments[i];
        return AppointmentCard(
          appointment: a,
          onTap: () => context.push('/appointments/${a.id}'),
        );
      },
    );
  }
}
