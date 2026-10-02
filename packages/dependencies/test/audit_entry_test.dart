import 'package:api_sdk/api_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String table = 'appointments',
  String action = 'update',
  Map<String, dynamic>? oldValues,
  Map<String, dynamic>? newValues,
  String? actorId = 'u1',
  String? actorName = 'Maria Santos',
  String? actorRole = 'doctor',
}) =>
    {
      'id': 7,
      'clinic_id': 'c1',
      'patient_id': 'p1',
      'patient_name': 'Ana Cruz',
      'table_name': table,
      'row_id': 'r1',
      'action': action,
      'old_values': oldValues,
      'new_values': newValues,
      'actor_id': actorId,
      'actor_name': actorName,
      'actor_role': actorRole,
      'tx_id': 99,
      'created_at': '2026-09-30T02:15:00+00:00',
    };

void main() {
  test('an update names the record, the new status and who did it', () {
    final e = AuditEntry.fromJson(_row(
      oldValues: {'status': 'pending'},
      newValues: {'status': 'in_consultation'},
    ));
    expect(e.headline, 'Visit in consultation');
    expect(e.actorLabel, 'Maria Santos');
    expect(e.actorRoleLabel, 'Doctor');
    expect(e.area, AuditArea.visits);
    final c = e.changes.single;
    expect((c.label, c.before, c.after), ('Status', 'Pending', 'In consultation'));
  });

  test('a reference to another record shows as changed, not as an id', () {
    final e = AuditEntry.fromJson(_row(
      oldValues: {'doctor_id': 'd1'},
      newValues: {'doctor_id': 'd2'},
    ));
    final c = e.changes.single;
    expect((c.label, c.before, c.after), ('Doctor', null, 'changed'));
  });

  test('a new patient lists who they are, without the ids', () {
    final e = AuditEntry.fromJson(_row(
      table: 'patients',
      action: 'insert',
      newValues: {
        'id': 'p1',
        'person_id': 'x',
        'created_by': 'u1',
        'chart_number': 'DT-7',
        'person': {'full_name': 'Ana Cruz', 'phone': '0917', 'sex': 'female', 'email': null},
      },
      actorRole: 'assistant',
    ));
    expect(e.headline, 'Patient registered');
    expect(e.actorRoleLabel, 'Front desk');
    expect(
      [for (final c in e.changes) '${c.label}=${c.after}'],
      ['Name=Ana Cruz', 'Phone=0917', 'Sex=Female', 'Chart no.=DT-7'],
    );
  });

  test('money, dates, flags and typed text read naturally', () {
    expect(formatAuditValue('amount', 1500), '₱1,500');
    expect(formatAuditValue('date_of_birth', '1990-04-02'), '2 Apr 1990');
    expect(formatAuditValue('is_active', false), 'No');
    expect(formatAuditValue('allergies', ['local_anesthetic', 'latex']),
        'Local anesthetic, Latex');
    expect(formatAuditValue('body', 'keep_this'), 'keep_this');
    expect(formatAuditValue('method', 'gcash'), 'Gcash');
    expect(formatAuditValue('phone', ''), isNull);
  });

  test('a delete shows the record as it was, and a voided payment says so', () {
    final gone = AuditEntry.fromJson(_row(
      table: 'expenses',
      action: 'delete',
      oldValues: {'amount': 250, 'description': 'Gloves'},
    ));
    expect(gone.headline, 'Expense removed');
    expect([for (final c in gone.changes) '${c.label}:${c.before}:${c.after}'],
        ['Amount:₱250:null', 'Description:Gloves:null']);

    final voided = AuditEntry.fromJson(_row(
      table: 'payments',
      oldValues: {'voided_at': null},
      newValues: {'voided_at': '2026-09-30T03:00:00+00:00'},
      actorRole: 'admin',
    ));
    expect(voided.headline, 'Payment voided');
  });

  test('a change nobody signed in made is the system’s', () {
    final e = AuditEntry.fromJson(
        _row(actorId: null, actorName: null, actorRole: null, newValues: {'price': 1}, oldValues: {'price': 2}));
    expect(e.actorLabel, 'System');
    expect(e.actorRoleLabel, isNull);
  });

  test('every staff app adds patients', () {
    expect(AppRole.doctor.registersPatients, isTrue);
    expect(AppRole.assistant.registersPatients, isTrue);
    expect(AppRole.admin.registersPatients, isTrue);
    expect(AppRole.patient.registersPatients, isFalse);
  });
}
