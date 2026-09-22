import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_role.dart';
import '../models/invoice.dart';
import 'catalog_provider.dart';
import 'clinic_provider.dart';
import 'clinical_provider.dart';
import 'supabase_providers.dart';

/// Whether the signed-in account may write bills at the current clinic.
/// Mirrors `private.can_bill`: the front desk and admins.
final canBillProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(currentClinicRoleProvider.future);
  return role == AppRole.assistant || role == AppRole.admin;
});

/// The current clinic's bills, newest first. Staff.
final clinicInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchInvoices(clinicId);
});

final invoiceProvider =
    FutureProvider.autoDispose.family<Invoice?, String>((ref, id) {
  return ref.watch(healthRepositoryProvider).fetchInvoice(id);
});

/// A visit's live bill, or null if it has none yet.
final appointmentInvoiceProvider =
    FutureProvider.autoDispose.family<Invoice?, String>((ref, appointmentId) {
  return ref.watch(healthRepositoryProvider).fetchAppointmentInvoice(appointmentId);
});

/// Bills on one chart, newest first. What a patient sees of their own chart
/// excludes drafts; staff see everything.
final patientInvoicesProvider =
    FutureProvider.autoDispose.family<List<Invoice>, String>((ref, patientId) {
  return ref.watch(healthRepositoryProvider).fetchPatientInvoices(patientId);
});

/// The signed-in patient's bills at the current clinic.
final myInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final chart = ref.watch(myPatientProvider).value;
  if (chart == null) return const [];
  return ref.watch(healthRepositoryProvider).fetchPatientInvoices(chart.id);
});

typedef BillingRange = ({DateTime from, DateTime to});

final billingSummaryProvider =
    FutureProvider.autoDispose.family<BillingSummary?, BillingRange>((ref, r) async {
  final clinicId = ref.watch(currentClinicIdProvider);
  if (clinicId == null) return null;
  return ref
      .watch(healthRepositoryProvider)
      .fetchBillingSummary(clinicId, from: r.from, to: r.to);
});

/// After any change to a bill, every view of bills refetches.
void invalidateBilling(WidgetRef ref) {
  ref.invalidate(clinicInvoicesProvider);
  ref.invalidate(invoiceProvider);
  ref.invalidate(appointmentInvoiceProvider);
  ref.invalidate(patientInvoicesProvider);
  ref.invalidate(myInvoicesProvider);
  ref.invalidate(billingSummaryProvider);
}
