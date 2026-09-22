import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:api_sdk/api_sdk.dart';

Map<String, dynamic> _person() => {
      'id': 'person-1',
      'full_name': 'Juan dela Cruz',
      'phone': '0917',
      'email': 'juan@email.com',
    };

Map<String, dynamic> _invoiceJson({
  String status = 'issued',
  Object total = 1500,
  Object paid = 500,
}) =>
    {
      'id': 'inv-1',
      'clinic_id': 'c1',
      'patient_id': 'chart-1',
      'appointment_id': 'appt-1',
      'number': status == 'draft' ? null : 'INV-000042',
      'status': status,
      'subtotal': '1500.00',
      'discount_amount': 0,
      'discount_reason': null,
      'total': total,
      'amount_paid': paid,
      'balance': 1000,
      'notes': null,
      'created_at': '2026-09-24T01:00:00Z',
      'issued_at': status == 'draft' ? null : '2026-09-24T02:00:00Z',
      'voided_at': null,
      'void_reason': null,
      'items': [
        {
          'id': 'line-1',
          'description': 'Root Canal',
          'quantity': 1,
          'unit_price': 1500,
          'amount': 1500,
          'service_id': 's1',
        },
      ],
      'payments': [
        {
          'id': 'pay-2',
          'amount': 200,
          'method': 'gcash',
          'reference': 'GC-1',
          'received_at': '2026-09-24T04:00:00Z',
          'voided_at': '2026-09-24T05:00:00Z',
          'void_reason': 'Wrong amount',
        },
        {
          'id': 'pay-1',
          'amount': '500.00',
          'method': 'cash',
          'reference': null,
          'received_at': '2026-09-24T03:00:00Z',
          'voided_at': null,
          'void_reason': null,
        },
      ],
      'patient': {
        'id': 'chart-1',
        'person_id': 'person-1',
        'clinic_id': 'c1',
        'person': _person(),
      },
      'appointment': {
        'service_name': 'Root Canal',
        'scheduled_at': '2026-09-24T01:00:00Z',
      },
    };

/// A browser whose push support and answers a test decides.
class FakePush implements BrowserPush {
  FakePush({
    this.supported = true,
    this.needsHomeScreenInstall = false,
    this.permission = 'default',
    this.grant = true,
  });

  @override
  final bool supported;
  @override
  final bool needsHomeScreenInstall;
  @override
  String permission;
  final bool grant;
  PushKeys? held;

  @override
  String get userAgent => 'test';

  @override
  Future<PushKeys?> current() async => held;

  @override
  Future<PushKeys?> subscribe(String vapidPublicKey) async {
    permission = grant ? 'granted' : 'denied';
    if (!grant) return null;
    return held = const PushKeys(endpoint: 'https://push.example/1', p256dh: 'k', auth: 'a');
  }

  @override
  Future<String?> unsubscribe() async {
    final endpoint = held?.endpoint;
    held = null;
    return endpoint;
  }

  @override
  void onNotificationOpened(void Function(String link) open) {}
}

/// Records the push calls instead of making them.
class FakeRepository extends HealthRepository {
  FakeRepository() : super(SupabaseClient('http://localhost', 'test-key'));

  final saved = <String>[];
  final deleted = <String>[];

  @override
  Future<void> savePushSubscription({
    required AppRole app,
    required String endpoint,
    required String p256dh,
    required String auth,
    String? userAgent,
  }) async =>
      saved.add('${app.wire} $endpoint');

  @override
  Future<void> deletePushSubscription(String endpoint) async =>
      deleted.add(endpoint);
}

({ProviderContainer container, FakeRepository repo}) pushContainer(FakePush push) {
  final repo = FakeRepository();
  final container = ProviderContainer(overrides: [
    appRoleProvider.overrideWithValue(AppRole.patient),
    currentUserIdProvider.overrideWithValue('u1'),
    browserPushProvider.overrideWithValue(push),
    healthRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

void main() {
  group('formatPeso', () {
    test('groups thousands and drops whole centavos', () {
      expect(formatPeso(1500), '₱1,500');
      expect(formatPeso(1234567.5), '₱1,234,567.50');
      expect(formatPeso(0), '₱0');
    });
    test('parseMoney takes numbers and numeric strings', () {
      expect(parseMoney('1500.00'), 1500);
      expect(parseMoney(12), 12.0);
      expect(parseMoney(null), 0);
    });
  });

  group('Invoice.fromJson', () {
    test('reads totals, lines, payments and embeds', () {
      final v = Invoice.fromJson(_invoiceJson());
      expect(v.status, InvoiceStatus.issued);
      expect(v.label, 'INV-000042');
      expect(v.subtotal, 1500);
      expect(v.balance, 1000);
      expect(v.isOpen, isTrue);
      expect(v.items.single.amount, 1500);
      expect(v.patient?.name, 'Juan dela Cruz');
      expect(v.title, 'Root Canal');
    });

    test('orders payments oldest first and keeps voided ones apart', () {
      final v = Invoice.fromJson(_invoiceJson());
      expect(v.payments.map((p) => p.id), ['pay-1', 'pay-2']);
      expect(v.activePayments.map((p) => p.id), ['pay-1']);
      expect(v.payments.last.method, PaymentMethod.gcash);
      expect(v.payments.last.isVoid, isTrue);
    });

    test("'void' on the wire is InvoiceStatus.voided", () {
      expect(InvoiceStatus.fromWire('void'), InvoiceStatus.voided);
      expect(Invoice.fromJson(_invoiceJson(status: 'void')).isOpen, isFalse);
    });

    test('a draft has no number yet', () {
      final v = Invoice.fromJson(_invoiceJson(status: 'draft'));
      expect(v.isDraft, isTrue);
      expect(v.label, 'Draft');
    });

    test('every payment method round-trips its wire name', () {
      for (final m in PaymentMethod.values) {
        expect(PaymentMethod.fromWire(m.wire), m);
      }
      expect(PaymentMethod.bankTransfer.wire, 'bank_transfer');
      expect(PaymentMethod.cash.wantsReference, isFalse);
    });

    test('BillingSummary reads takings by method', () {
      final s = BillingSummary.fromJson({
        'collected': 500,
        'by_method': {'gcash': 300, 'cash': '200.00'},
        'billed': 1500,
        'outstanding': 1000,
        'unpaid_count': 1,
        'draft_count': 0,
      });
      expect(s.byMethod[PaymentMethod.gcash], 300);
      expect(s.byMethod[PaymentMethod.cash], 200);
      expect(s.outstanding, 1000);
    });
  });

  group('Appointment rescheduling', () {
    Map<String, dynamic> json(String status, {String? from}) => {
          'id': 'a1',
          'clinic_id': 'c1',
          'patient': {
            'id': 'chart-1',
            'person_id': 'person-1',
            'clinic_id': 'c1',
            'person': _person(),
          },
          'doctor': {
            'id': 'd1',
            'clinic_id': 'c1',
            'full_name': 'Maria Santos',
            'specialty': 'General Dentistry',
          },
          'scheduled_at': '2030-01-07T01:00:00Z',
          'service_name': 'Check-up',
          'status': status,
          'rescheduled_from': from,
          'reschedule_count': from == null ? 0 : 1,
        };

    test('carries where it was moved from', () {
      final a = Appointment.fromJson(json('pending', from: '2030-01-06T01:00:00Z'));
      expect(a.rescheduledFrom, DateTime.utc(2030, 1, 6, 1).toLocal());
      expect(a.rescheduleCount, 1);
    });

    test('only a visit that has not started can move', () {
      expect(Appointment.fromJson(json('pending')).canReschedule, isTrue);
      expect(Appointment.fromJson(json('confirmed')).canReschedule, isTrue);
      expect(Appointment.fromJson(json('arrived')).canReschedule, isFalse);
      expect(Appointment.fromJson(json('cancelled')).canReschedule, isFalse);
    });
  });

  test('AppNotification.fromJson', () {
    final n = AppNotification.fromJson({
      'id': 'n1',
      'app': 'patient',
      'kind': 'visit_confirmed',
      'title': 'Visit confirmed',
      'body': 'Check-up on Mon',
      'link': '/dtouchdental/appointments/a1',
      'clinic_id': 'c1',
      'appointment_id': 'a1',
      'created_at': '2026-09-24T01:00:00Z',
      'read_at': null,
    });
    expect(n.app, AppRole.patient);
    expect(n.isRead, isFalse);
    expect(n.link, '/dtouchdental/appointments/a1');
  });

  group('PushSettings', () {
    test('a browser without the Push API is unsupported', () async {
      final c = pushContainer(FakePush(supported: false)).container;
      expect(await c.read(pushSettingsProvider.future), PushState.unsupported);
    });

    test('iPhone Safari is told to add the site to the home screen', () async {
      final c = pushContainer(FakePush(supported: false, needsHomeScreenInstall: true)).container;
      expect(await c.read(pushSettingsProvider.future), PushState.needsHomeScreen);
    });

    test('blocked notifications are reported, not re-asked', () async {
      final c = pushContainer(FakePush(permission: 'denied')).container;
      expect(await c.read(pushSettingsProvider.future), PushState.blocked);
    });

    test('turning on subscribes and registers this browser for this app', () async {
      final (:container, :repo) = pushContainer(FakePush());
      expect(await container.read(pushSettingsProvider.future), PushState.off);
      await container.read(pushSettingsProvider.notifier).enable();
      expect(container.read(pushSettingsProvider).value, PushState.on);
      expect(repo.saved, ['patient https://push.example/1']);
    });

    test('saying no leaves it blocked, and registers nothing', () async {
      final (:container, :repo) = pushContainer(FakePush(grant: false));
      await container.read(pushSettingsProvider.future);
      await container.read(pushSettingsProvider.notifier).enable();
      expect(container.read(pushSettingsProvider).value, PushState.blocked);
      expect(repo.saved, isEmpty);
    });

    test('turning off forgets the subscription on both sides', () async {
      final push = FakePush(permission: 'granted')
        ..held = const PushKeys(endpoint: 'https://push.example/1', p256dh: 'k', auth: 'a');
      final (:container, :repo) = pushContainer(push);
      expect(await container.read(pushSettingsProvider.future), PushState.on);
      await container.read(pushSettingsProvider.notifier).disable();
      expect(container.read(pushSettingsProvider).value, PushState.off);
      expect(repo.deleted, ['https://push.example/1']);
      expect(push.held, isNull);
    });
  });
}
