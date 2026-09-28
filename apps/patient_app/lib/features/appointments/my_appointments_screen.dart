import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    // Upcoming: still to come, or happening now (checked in, or with the
    // doctor, even though the start time has passed).
    bool isUpcoming(Appointment a) =>
        a.status.holdsTime && (a.dateTime.isAfter(now) || a.status.isOnSite);
    final upcoming = all.where(isUpcoming).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    // Recent past visits are in the loaded window; older ones page in below.
    final past = all.where((a) => !isUpcoming(a)).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final me = ref.watch(myPatientProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Upcoming (${upcoming.length})'),
            const Tab(text: 'Past'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushInClinic('/book'),
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
              PastAppointmentsList(
                recent: past,
                query: (doctorId: null, patientId: me?.id),
                emptyMessage: 'No past appointments',
                emptySubtitle: 'Your appointment history will appear here',
                itemBuilder: (context, a) => AppointmentCard(
                  appointment: a,
                  onTap: () => context.pushInClinic('/appointments/${a.id}'),
                ),
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
    return CenteredScroll(
      maxWidth: ContentWidth.list,
      padding: const EdgeInsets.all(16),
      builder: (padding) => ListView.separated(
        padding: padding,
        itemCount: appointments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final a = appointments[i];
          return AppointmentCard(
            appointment: a,
            onTap: () => context.pushInClinic('/appointments/${a.id}'),
          );
        },
      ),
    );
  }
}
