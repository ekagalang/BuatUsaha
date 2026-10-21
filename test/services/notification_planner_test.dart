import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/day_close_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/services/notification_planner.dart';
import 'package:buat_usaha/services/notification_scheduler.dart';
import 'package:buat_usaha/services/notification_sync.dart';

import '../support/seed.dart';

class FakeScheduler implements NotificationScheduler {
  final scheduled = <List<PlannedNotification>>[];
  final shown = <PlannedNotification>[];

  @override
  Future<void> replaceScheduled(List<PlannedNotification> n) async =>
      scheduled.add(n);

  @override
  Future<void> showNow(PlannedNotification n) async => shown.add(n);
}

void main() {
  late Seed s;
  late NotificationPlanner planner;

  setUp(() async {
    s = await Seed.create();
    planner = NotificationPlanner(s.db);
  });
  tearDown(() => s.close());

  DateTime local(int day, [int hour = 10, int minute = 0]) =>
      DateTime(2026, 10, day, hour, minute);

  Future<String> order({DateTime? due, List<ReminderInput>? reminders}) =>
      s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: due ?? local(21),
          customerName: 'Bu Rina',
          reminders: reminders,
          items: [
            OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
          ],
        ),
      );

  test('pengingat pesanan H-1 dan 2 jam sebelum + ringkasan harian', () async {
    final id = await order();
    final plan = await planner.plan(now: local(20, 7));

    final orderOnes = plan.where((n) => n.channel == NotifyChannel.orders);
    expect(orderOnes.map((n) => n.at), [local(20, 8), local(21, 8)]);
    expect(orderOnes.first.title, 'Pesanan Bu Rina · 10.00');
    expect(
      orderOnes.first.body,
      'Besok 21 Okt: 10 Brownies · diambil · sisa Rp80.000',
    );
    expect(orderOnes.last.body, startsWith('Jam 10.00: '));
    expect(orderOnes.first.payload, 'order:$id');

    final summary = plan.where((n) => n.channel == NotifyChannel.summary);
    expect(summary.single.at, local(21, 6));
    expect(summary.single.body, 'Hari ini 1 pesanan, 1 belum lunas');
  });

  test(
    'jam tenang menggeser pengingat; pesanan selesai tidak diingatkan',
    () async {
      await s.business.updateNotificationSettings(
        s.businessId,
        const NotificationSettingsCompanion(
          quietStart: Value('21:00'),
          quietEnd: Value('07:00'),
        ),
      );
      await order(reminders: [ReminderInput.custom(local(20, 22))]);
      final plan = await planner.plan(now: local(20, 12));
      final reminder = plan.firstWhere(
        (n) => n.channel == NotifyChannel.orders,
      );
      expect(reminder.at, local(21, 7));
    },
  );

  test('pengingat pelunasan untuk pesanan Siap yang belum lunas', () async {
    final id = await order(due: local(20, 8), reminders: const []);
    await s.orders.setStatus(id, OrderStatus.ready);
    var plan = await planner.plan(now: local(20, 10));
    final pay = plan.where((n) => n.channel == NotifyChannel.payments);
    expect(pay.single.at, local(21, 9));
    expect(pay.single.body, contains('sisa Rp80.000'));

    await s.orders.addPayment(
      id,
      amount: 80000,
      method: PaymentMethod.cash,
      kind: PaymentKind.settlement,
    );
    plan = await planner.plan(now: local(20, 10));
    expect(plan.where((n) => n.channel == NotifyChannel.payments), isEmpty);
  });

  test(
    'pengingat Tutup hari hanya jika ada sisa dan hari belum ditutup',
    () async {
      final now = DateTime.now();
      if (now.hour >= 19) return; // jam Tutup hari bawaan 20.00 sudah dekat.
      var plan = await planner.plan(now: now);
      expect(plan.where((n) => n.channel == NotifyChannel.dayClose), isEmpty);

      await s.products.recordProduction(s.brownies, batchQty: d('1'), at: now);
      plan = await planner.plan(now: now);
      final close = plan.singleWhere(
        (n) => n.channel == NotifyChannel.dayClose,
      );
      expect(close.body, startsWith('Masih ada sisa 1 menu'));
      expect(close.payload, 'day-close');

      await DayCloseRepository(
        s.db,
        s.products,
      ).closeDay(s.businessId, now, []);
      plan = await planner.plan(now: now);
      expect(plan.where((n) => n.channel == NotifyChannel.dayClose), isEmpty);
    },
  );

  test('stok menipis diberi tahu sekali sampai stok diisi lagi', () async {
    final sync = FakeScheduler();
    await s.stock.updateIngredient(s.ids['cokelat']!, minStock: d('400'));
    final service = NotificationSync(s.db, sync, clock: () => local(20, 7));
    await service.resync();
    expect(sync.shown.single.title, 'Stok Cokelat menipis');
    expect(sync.shown.single.payload, 'ingredient:${s.ids['cokelat']}');

    await service.resync();
    expect(sync.shown, hasLength(1));
    expect(sync.scheduled, hasLength(2));
    await service.dispose();
  });
}
