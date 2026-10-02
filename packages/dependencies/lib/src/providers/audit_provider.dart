import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/audit_entry.dart';
import 'clinical_provider.dart';
import 'supabase_providers.dart';

/// Reads the activity log (`public.audit_entries`). The database returns rows
/// to the clinic's admins only; for anyone else every page is empty.
class AuditRepository {
  AuditRepository(this._db);

  final SupabaseClient _db;

  static const pageSize = 50;

  /// Newest first. [beforeId] continues from the last entry of the previous
  /// page, so entries logged while someone reads do not shift the pages.
  Future<AuditPage> fetch({
    required String clinicId,
    String? patientId,
    AuditArea? area,
    int? beforeId,
  }) async {
    var q = _db.from('audit_entries').select().eq('clinic_id', clinicId);
    if (patientId != null) q = q.eq('patient_id', patientId);
    if (area != null) q = q.inFilter('table_name', area.tables);
    if (beforeId != null) q = q.lt('id', beforeId);
    final rows =
        await q.order('id', ascending: false).limit(pageSize + 1) as List<dynamic>;
    final entries = [
      for (final r in rows.take(pageSize))
        AuditEntry.fromJson(r as Map<String, dynamic>),
    ];
    return AuditPage(entries, hasMore: rows.length > pageSize);
  }
}

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(ref.watch(supabaseClientProvider)),
);

/// Whether the signed-in user may read the activity log here: admins only,
/// as `audit_log_select_admin` decides.
final canSeeAuditLogProvider = Provider<bool>((ref) =>
    ref.watch(currentClinicRoleProvider).value == AppRole.admin);
