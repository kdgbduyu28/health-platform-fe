import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/clinic_router.dart';
import '../models/patient.dart';
import '../models/patient_intake.dart';
import '../providers/catalog_provider.dart';
import '../providers/clinic_provider.dart';
import '../providers/clinical_provider.dart';
import '../providers/intake_provider.dart';
import '../providers/supabase_providers.dart';
import '../theme/brand.dart';
import 'async_view.dart';
import 'patient_intake_form.dart';
import 'staff_pin.dart';

// ── Starting a form from the staff apps ─────────────────────────────────────

/// "Add patient": the front desk fills the form in, or hands the tablet over.
/// Returns the new chart when the front desk filled it in; the hand-off
/// returns nothing, since the app is on the tablet screen by then.
Future<Patient?> showAddPatientSheet(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<_AddChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add patient',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _ChoiceTile(
              icon: Icons.tablet_android_outlined,
              title: 'Hand the tablet to the patient',
              subtitle: 'They fill in their own details and health history. '
                  'Your staff PIN takes the tablet back.',
              onTap: () => Navigator.pop(context, _AddChoice.handOver),
            ),
            const SizedBox(height: 8),
            _ChoiceTile(
              icon: Icons.edit_note,
              title: 'Fill in the form myself',
              subtitle: 'For a patient on the phone, or reading it out.',
              onTap: () => Navigator.pop(context, _AddChoice.myself),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;

  switch (choice) {
    case _AddChoice.handOver:
      await startKiosk(context, ref);
      return null;
    case _AddChoice.myself:
      final id = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => const StaffIntakeScreen(),
      ));
      if (id == null) return null;
      invalidatePatientLists(ref);
      return ref.read(healthRepositoryProvider).fetchPatient(id);
  }
}

enum _AddChoice { handOver, myself }

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Hands the tablet to a patient: the form for [patientId], or for a new
/// patient. Asks the staff member to set a PIN first if they have none.
Future<void> startKiosk(BuildContext context, WidgetRef ref,
    {String? patientId}) async {
  final slug = ref.read(routeClinicSlugProvider);
  if (slug == null) return;
  if (!await ensureStaffPin(context, ref)) return;
  if (!context.mounted) return;
  final ready = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.tablet_android_outlined),
      title: const Text('Hand the tablet over?'),
      content: const Text(
          'The app will show only the form until you enter your staff PIN. '
          'The patient cannot leave it or see anything else.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Start'),
        ),
      ],
    ),
  );
  if (ready != true || !context.mounted) return;
  ref.read(kioskProvider.notifier).start(slug: slug, patientId: patientId);
  context.go('/$slug/kiosk');
}

// ── The front desk typing it in ─────────────────────────────────────────────

/// The form, filled in by staff: a new patient (no [patient]), or the form on
/// an existing chart. Pops with the chart id once saved.
class StaffIntakeScreen extends ConsumerWidget {
  const StaffIntakeScreen({super.key, this.patient});

  final Patient? patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existing = patient;
    final clinic = ref.watch(currentClinicProvider).value;
    final canHandOver = ref.watch(appRoleProvider).registersPatients;
    final intake =
        existing == null ? null : ref.watch(intakeProvider(existing.id));

    final guard = intake == null
        ? null
        : asyncGuard(intake,
            appBar: AppBar(title: const Text('Patient information')),
            onRetry: () => ref.invalidate(intakeProvider(existing!.id)));
    if (guard != null) return guard;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'New patient' : existing.name),
        actions: [
          if (canHandOver)
            TextButton.icon(
              // Nothing typed here carries over: the tablet opens its own
              // form, and going there closes this screen.
              onPressed: () => startKiosk(context, ref, patientId: existing?.id),
              icon: const Icon(Icons.tablet_android_outlined),
              label: const Text('Hand to patient'),
            ),
        ],
      ),
      body: PatientIntakeForm(
        audience: IntakeAudience.staff,
        clinicName: clinic?.name ?? 'the clinic',
        isDental: clinic?.isDental ?? false,
        patient: existing,
        intake: intake?.value,
        submitLabel: 'Save',
        onSubmit: (form) async {
          final repo = ref.read(healthRepositoryProvider);
          final String id;
          if (existing == null) {
            id = await repo.registerPatient(
                clinicId: clinic!.id, form: form, source: IntakeSource.staff);
          } else {
            await repo.savePatientIntake(
                patientId: existing.id, form: form, source: IntakeSource.staff);
            id = existing.id;
            ref
              ..invalidate(intakeProvider(id))
              ..invalidate(patientByIdProvider(id));
            invalidatePatientLists(ref);
          }
          if (context.mounted) Navigator.pop(context, id);
        },
      ),
    );
  }
}

// ── The tablet, in the patient's hands ──────────────────────────────────────

/// `/:clinic/kiosk`: the form, and nothing else, until a staff PIN.
///
/// The router sends every other URL here while [kioskProvider] holds a
/// session, so neither the back button, a typed URL nor a reload gets the
/// patient into the app. The clinic switcher is deliberately absent too.
class KioskScreen extends ConsumerWidget {
  const KioskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kioskProvider);
    final clinic = ref.watch(currentClinicProvider).value;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Future<void> unlock() async {
      if (!await showStaffPinDialog(context, allowSignOut: true)) return;
      final id = ref.read(kioskProvider)?.patientId;
      ref.read(kioskProvider.notifier).end();
      invalidatePatientLists(ref);
      if (id != null) {
        ref
          ..invalidate(intakeProvider(id))
          ..invalidate(patientByIdProvider(id));
      }
      if (context.mounted) {
        context.go('/${session.slug}/patients${id == null ? '' : '/$id'}');
      }
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              ClinicMark(clinic: clinic, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(clinic?.name ?? '', overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: unlock,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Staff'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: session.submitted
            ? _KioskThanks(onUnlock: unlock)
            : _KioskForm(session: session),
      ),
    );
  }
}

class _KioskForm extends ConsumerWidget {
  const _KioskForm({required this.session});

  final KioskSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;
    final id = session.patientId;

    Patient? patient;
    PatientIntake? intake;
    if (id != null) {
      final p = ref.watch(patientByIdProvider(id));
      final i = ref.watch(intakeProvider(id));
      if (!p.hasValue || !i.hasValue) {
        return AsyncView(
          value: p.hasValue ? i : p,
          onRetry: () => ref
            ..invalidate(patientByIdProvider(id))
            ..invalidate(intakeProvider(id)),
          builder: (_) => const SizedBox.shrink(),
        );
      }
      patient = p.value;
      intake = i.value;
    }

    return PatientIntakeForm(
      // A fresh form per hand-off: never the previous patient's answers.
      key: ValueKey(id ?? 'new'),
      audience: IntakeAudience.patient,
      clinicName: clinic?.name ?? 'the clinic',
      isDental: clinic?.isDental ?? false,
      patient: patient,
      intake: intake,
      submitLabel: 'Send',
      onSubmit: (form) async {
        final repo = ref.read(healthRepositoryProvider);
        final chartId = id ??
            await repo.registerPatient(
                clinicId: clinic!.id,
                form: form,
                source: IntakeSource.frontDeskTablet);
        if (id != null) {
          await repo.savePatientIntake(
              patientId: id, form: form, source: IntakeSource.frontDeskTablet);
        }
        ref.read(kioskProvider.notifier).submitted(chartId);
      },
    );
  }
}

class _KioskThanks extends StatelessWidget {
  const _KioskThanks({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.check_rounded,
                    size: 56, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Text('Thank you!',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'Your information has been sent. Please hand the tablet back '
                'to the front desk.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Front desk: unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The patient app ─────────────────────────────────────────────────────────

/// `/:clinic/intake` in the patient app: the form for the signed-in patient's
/// chart at this clinic.
///
/// Until it has been filled in once, the router sends every page at this
/// clinic here — right after sign-up and joining, before the home screen.
/// After that it is where the profile's "My information" leads.
class MyIntakeScreen extends ConsumerWidget {
  const MyIntakeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinic = ref.watch(currentClinicProvider).value;
    final me = ref.watch(myPatientProvider);
    final guard = asyncGuard(me,
        appBar: AppBar(title: const Text('My information')),
        onRetry: () => ref.invalidate(myPatientsProvider));
    if (guard != null) return guard;
    final patient = me.requireValue;
    if (patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My information')),
        body: const Center(child: Text('No chart at this clinic.')),
      );
    }

    final intake = ref.watch(intakeProvider(patient.id));
    final firstTime = patient.hasIntake == false;
    final intakeGuard = asyncGuard(intake,
        appBar: AppBar(title: const Text('My information')),
        onRetry: () => ref.invalidate(intakeProvider(patient.id)));
    if (intakeGuard != null) return intakeGuard;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !firstTime,
        title: Text(firstTime
            ? 'Welcome to ${clinic?.name ?? 'the clinic'}'
            : 'My information'),
        actions: [
          if (firstTime)
            TextButton(
              onPressed: () => ref.read(healthRepositoryProvider).signOut(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (firstTime)
            MaterialBanner(
              content: const Text(
                  'Before your first visit, please tell the clinic a little '
                  'about yourself. It takes about 3 minutes.'),
              leading: const Icon(Icons.assignment_ind_outlined),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: PatientIntakeForm(
              audience: IntakeAudience.patient,
              clinicName: clinic?.name ?? 'the clinic',
              isDental: clinic?.isDental ?? false,
              patient: patient,
              intake: intake.value,
              submitLabel: firstTime ? 'Send' : 'Save',
              onSubmit: (form) async {
                await ref.read(healthRepositoryProvider).savePatientIntake(
                    patientId: patient.id,
                    form: form,
                    source: IntakeSource.patientApp);
                ref.invalidate(intakeProvider(patient.id));
                // The router's gate reads this; it must see the form as done
                // before the app moves on.
                ref.invalidate(myPatientsProvider);
                await ref.read(myPatientsProvider.future);
                if (!context.mounted) return;
                if (!firstTime && context.canPop()) {
                  context.pop();
                } else {
                  context.goInClinic('/home');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── On the patient's page (staff apps) ──────────────────────────────────────

/// The form on file, summarised for the staff apps: allergies first, then
/// medicines and conditions. Every staff member sees it — the front desk
/// included, by the clinic's choice. Staff can edit it; the front desk and
/// admins can also hand the tablet over to have the patient update it.
class IntakeSection extends ConsumerWidget {
  const IntakeSection({super.key, required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    if (!app.isStaff) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final intakeAsync = ref.watch(intakeProvider(patient.id));

    Future<void> edit() async {
      final saved = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => StaffIntakeScreen(patient: patient),
      ));
      if (saved != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Patient information saved'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (app.registersPatients)
          FilledButton.tonalIcon(
            onPressed: () => startKiosk(context, ref, patientId: patient.id),
            icon: const Icon(Icons.tablet_android_outlined, size: 18),
            label: const Text('Hand to patient'),
          ),
        OutlinedButton.icon(
          onPressed: edit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(intakeAsync.value == null ? 'Fill in' : 'Edit'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AsyncView(
            value: intakeAsync,
            onRetry: () => ref.invalidate(intakeProvider(patient.id)),
            builder: (intake) {
              if (intake == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(),
                    const SizedBox(height: 4),
                    Text(
                        'Not filled in yet. Ask about allergies and medicines '
                        'before treatment.',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    actions,
                  ],
                );
              }

              final female = patient.sex == Sex.female;
              final flags = [
                if (female && intake.pregnant == true) 'Pregnant',
                if (female && intake.nursing == true) 'Breastfeeding',
                if (female && intake.birthControl == true) 'On birth control pills',
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(),
                  Text(
                    'Filled in ${intake.source.description} · '
                    '${DateFormat('MMM d, y').format(intake.updatedAt)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (intake.guardian case final g?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Line(
                          'Filled in by',
                          [
                            '${g.name} (${g.relationship.label})',
                            g.phone,
                            if (g.email != null) g.email!,
                          ].join(' · ')),
                    ),
                  const SizedBox(height: 12),
                  if (intake.hasAllergies)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: cs.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Allergic to ${intake.allergyLabels.join(', ')}',
                              style: TextStyle(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const _Line('Allergies', 'None reported'),
                  _Line('Medicines',
                      intake.takesMedications ? (intake.medications ?? 'Yes') : 'None'),
                  _Line(
                      'Conditions',
                      intake.conditionLabels.isEmpty
                          ? 'None reported'
                          : intake.conditionLabels.join(', ')),
                  if (intake.underTreatment)
                    _Line('Under treatment', intake.treatmentDetails ?? 'Yes'),
                  if (flags.isNotEmpty) _Line('Also', flags.join(' · ')),
                  if (intake.physicianName != null)
                    _Line('Physician', intake.physicianName!),
                  if (intake.lastDentalVisit != null)
                    _Line('Last dental visit', intake.lastDentalVisit!),
                  if (intake.reasonForVisit != null)
                    _Line('Reason for visit', intake.reasonForVisit!),
                  if (patient.emergencyContactName != null ||
                      patient.emergencyContactPhone != null)
                    _Line(
                        'Emergency contact',
                        [patient.emergencyContactName, patient.emergencyContactPhone]
                            .whereType<String>()
                            .join(' · ')),
                  if (patient.address != null) _Line('Address', patient.address!),
                  if (patient.sex != null) _Line('Sex', patient.sex!.label),
                  if (patient.occupation != null)
                    _Line('Occupation', patient.occupation!),
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.assignment_ind_outlined,
            size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        const Text('Patient information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
