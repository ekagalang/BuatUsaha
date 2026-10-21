import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/day_close_repository.dart';
import 'package:buat_usaha/data/repositories/expense_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/product_repository.dart';
import 'package:buat_usaha/data/repositories/report_repository.dart';
import 'package:buat_usaha/domain/costing/costing.dart';

import '../support/seed.dart';

void main() {
  late Seed s;
  late DayCloseRepository dayClose;
  late ReportRepository reports;
  late ExpenseRepository expenses;
  late String cookies;

  setUp(() async {
    s = await Seed.create();
    dayClose = DayCloseRepository(s.db, s.products);
    reports = ReportRepository(s.db);
    expenses = ExpenseRepository(s.db);
    // Cookies toples: HPP Rp18.000, jual Rp30.000 (angka ilustrasi PRD).
    final adonan = (await s.stock.createIngredient(
      businessId: s.businessId,
      name: 'Adonan cookies',
      baseUnit: BaseUnit.g,
      openingQty: d('1800'),
      openingUnitCost: d('100'),
      at: DateTime.utc(2026, 10, 1),
    )).id;
    cookies = await s.products.createProduct(
      s.businessId,
      ProductInput(
        name: 'Cookies toples',
        sellingPrice: 30000,
        yieldQty: d('10'),
        recipe: [RecipeInput(ingredientId: adonan, qtyBase: d('1800'))],
      ),
    );
  });
  tearDown(() => s.close());

  Future<void> sell(String productId, int qty, int price) =>
      s.orders.recordDirectSale(
        s.businessId,
        OrderInput(
          dueAt: DateTime.now(),
          items: [
            OrderItemInput(productId: productId, qty: qty, unitPrice: price),
          ],
        ),
      );

  Future<String> category(String name) async =>
      (await expenses.watchCategories(s.businessId).first)
          .firstWhere((c) => c.name == name)
          .id;

  test('ringkasan satu hari sesuai contoh PRD bagian 6', () async {
    final now = DateTime.now();
    await s.products.recordProduction(s.brownies, batchQty: d('1.5'), at: now);
    await s.products.recordProduction(cookies, batchQty: Decimal.one, at: now);
    await sell(s.brownies, 25, 8000);
    await sell(cookies, 4, 30000);

    final left = await dayClose.leftovers(s.businessId, now);
    expect(left.map((l) => l.product.name), ['Brownies', 'Cookies toples']);
    expect(left.first.stock, d('5'));
    expect(left.first.lossFor(d('5')), 24175);

    await dayClose.closeDay(s.businessId, now, [
      DiscardInput(productId: s.brownies, qty: d('5')),
    ]);
    expect((await s.product(s.brownies)).stock, Decimal.zero);
    expect((await s.product(cookies)).stock, d('6'));
    expect(await dayClose.isClosed(s.businessId, now), isTrue);

    await expenses.addExpense(
      s.businessId,
      categoryId: await category('Transport'),
      amount: 20000,
      spentAt: now,
      note: 'ojek',
    );
    await expenses.addExpense(
      s.businessId,
      categoryId: await category('Sewa'),
      amount: 500000,
      spentAt: now,
      isMonthly: true,
    );

    final day = await reports.dayReport(s.businessId, now);
    final brownies = day.products.firstWhere((p) => p.product.id == s.brownies);
    expect(brownies.made, d('30'));
    expect(brownies.sold, 25);
    expect(brownies.discarded, d('5'));
    expect(brownies.kept, Decimal.zero);
    expect(brownies.profit, d('54950'));
    final cookie = day.products.firstWhere((p) => p.product.id == cookies);
    expect(cookie.made, d('10'));
    expect(cookie.kept, d('6'));
    expect(cookie.profit, d('48000'));

    expect(day.summary.revenue, 320000);
    expect(day.summary.cogs, 192875);
    expect(day.summary.wasteLoss, 24175);
    expect(day.summary.menuProfit, 102950);
    expect(day.summary.expenses, 20000);
    expect(day.summary.netProfit, 82950);
    expect(day.summary.status, DayStatus.profit);
    expect(day.mostPressuring?.product.id, s.brownies);
    expect(day.closed, isTrue);

    final start = startOfDay(now);
    final period = await reports.periodReport(
      s.businessId,
      start,
      start.add(const Duration(days: 1)),
    );
    expect(period.revenue, 320000);
    expect(period.grossProfit, 127125);
    expect(period.productLoss, 24175);
    expect(period.expenses, 520000);
    expect(period.netProfit, 127125 - 24175 - 520000);
    expect(period.bestSellers.first.product.id, s.brownies);
    expect(period.mostProfitable.first.profit, d('79125'));
    expect(period.channels.single.name, 'Langsung');
    expect(period.orders, 2);
    expect(period.trend.single.profit, 127125 - 24175);
  });

  test('sisa disimpan bukan rugi; Tutup hari bisa dibatalkan', () async {
    final now = DateTime.now();
    await s.products.recordProduction(s.brownies, batchQty: d('1.5'), at: now);
    await sell(s.brownies, 25, 8000);
    await dayClose.closeDay(s.businessId, now, [
      DiscardInput(productId: s.brownies, qty: d('5')),
    ]);
    await dayClose.voidDayClose(now, reason: 'ternyata masih bagus');
    final day = await reports.dayReport(s.businessId, now);
    expect(day.summary.wasteLoss, 0);
    // Jika 5 brownies disimpan, laba hari itu Rp79.125 (bagian dari contoh
    // PRD: 127.125 dengan cookies).
    expect(day.summary.menuProfit, 79125);
    expect((await s.product(s.brownies)).stock, d('5'));
  });

  test(
    'umur simpan: habis besok di hari ke-3, lewat umur di hari ke-4',
    () async {
      await s.products.recordProduction(
        s.brownies,
        batchQty: Decimal.one,
        at: DateTime(2026, 10, 1, 9),
      );
      var left = (await dayClose.leftovers(
        s.businessId,
        DateTime(2026, 10, 3, 20),
      )).single;
      expect(left.expiresTomorrowQty, d('20'));
      expect(left.expiredQty, Decimal.zero);

      left = (await dayClose.leftovers(
        s.businessId,
        DateTime(2026, 10, 4, 20),
      )).single;
      expect(left.expiredQty, d('20'));
    },
  );

  test('channel dan potongan masuk laporan per channel', () async {
    final now = DateTime.now();
    await s.products.recordProduction(s.brownies, batchQty: d('1'), at: now);
    final mitra = await s.channel('Mitra 20%', '20');
    await s.orders.recordDirectSale(
      s.businessId,
      OrderInput(
        dueAt: now,
        channelId: mitra,
        items: [
          OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
        ],
      ),
    );
    await sell(s.brownies, 10, 8000);
    final start = startOfDay(now);
    final period = await reports.periodReport(
      s.businessId,
      start,
      start.add(const Duration(days: 1)),
    );
    final byName = {for (final c in period.channels) c.name: c};
    expect(byName['Mitra 20%']!.fee, 16000);
    expect(byName['Mitra 20%']!.profit, d('15650'));
    expect(byName['Langsung']!.profit, d('31650'));
    expect(period.marginPct, d('29.6'));
  });
}
