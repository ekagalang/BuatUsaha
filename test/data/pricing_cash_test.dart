import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/cash_repository.dart';
import 'package:buat_usaha/data/repositories/expense_repository.dart';
import 'package:buat_usaha/data/repositories/hpp_refresher.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/pricing_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/domain/costing/costing.dart';

import '../support/seed.dart';

void main() {
  late Seed s;
  late PricingRepository pricing;
  late CashRepository cash;

  setUp(() async {
    s = await Seed.create();
    pricing = PricingRepository(s.db, s.products);
    cash = CashRepository(s.db);
  });
  tearDown(() => s.close());

  Future<String> buy(String key, int grams, int total, {String? account}) =>
      s.stock.recordPurchase(
        s.businessId,
        PurchaseInput(
          purchasedAt: DateTime(2026, 10, 20, 7),
          cashAccountId: account,
          lines: [
            PurchaseLineInput(
              ingredientId: s.ids[key]!,
              qty: Decimal.fromInt(grams),
              unitName: 'g',
              factorToBase: Decimal.one,
              totalPrice: total,
            ),
          ],
        ),
      );

  Future<List<ProductHppHistoryData>> history() =>
      pricing.watchHppHistory(s.brownies).first;

  group('harga per channel', () {
    test('saran harga: komisi dan biaya per pesanan', () {
      expect(
        suggestChannelPrice(
          directPrice: 8000,
          commissionPct: d('20'),
          avgPcsPerOrder: Decimal.one,
        ),
        10000,
      );
      // (8.000 + 2.000 ÷ 10) ÷ 0,8 = 10.250 → 10.500.
      expect(
        suggestChannelPrice(
          directPrice: 8000,
          commissionPct: d('20'),
          feePerOrder: 2000,
          avgPcsPerOrder: d('10'),
        ),
        10500,
      );
      expect(
        suggestChannelPrice(
          directPrice: 8000,
          commissionPct: d('100'),
          avgPcsPerOrder: Decimal.one,
        ),
        isNull,
      );
    });

    test('harga khusus disimpan, dipakai, lalu dikembalikan', () async {
      final gofood = await s.channel('GoFood 20%', '20');
      final product = (await s.product(s.brownies)).product;
      await pricing.setChannelPrice(s.brownies, gofood, price: 10000);
      var prices = await pricing.watchChannelPrices(s.businessId).first;
      expect(priceFor(product, gofood, prices), 10000);
      expect(priceFor(product, null, prices), 8000);

      final row = (await pricing.channelRows(
        s.brownies,
        s.businessId,
      )).firstWhere((r) => r.channel.id == gofood);
      expect(row.customPrice, 10000);
      expect(row.feePerPcs, d('2000'));
      // 10.000 − 2.000 − HPP 4.835.
      expect(row.profitPerPcs, d('3165'));
      expect(row.suggestion, 10000);

      await pricing.setChannelPrice(s.brownies, gofood, price: null);
      prices = await pricing.watchChannelPrices(s.businessId).first;
      expect(priceFor(product, gofood, prices), 8000);
    });

    test('rata-rata pcs per pesanan dari pesanan selesai channel', () async {
      final gofood = await s.channel('GoFood 20%', '20');
      expect(await pricing.averagePcsPerOrder(s.businessId, gofood), d('1'));
      await s.products.recordProduction(
        s.brownies,
        batchQty: d('1'),
        at: DateTime.utc(2026, 10, 15),
      );
      for (final qty in [4, 8]) {
        final id = await s.orders.createOrder(
          s.businessId,
          OrderInput(
            dueAt: DateTime(2026, 10, 21, 10),
            channelId: gofood,
            items: [
              OrderItemInput(productId: s.brownies, qty: qty, unitPrice: 10000),
            ],
          ),
        );
        await s.orders.completeOrder(id, at: DateTime(2026, 10, 21, 11));
      }
      expect(await pricing.averagePcsPerOrder(s.businessId, gofood), d('6'));
      // Channel lain belum ada pesanan → rata-rata semua pesanan.
      final grab = await s.channel('GrabFood', '25');
      expect(await pricing.averagePcsPerOrder(s.businessId, grab), d('6'));
    });
  });

  group('riwayat HPP', () {
    test('dicatat saat menu dibuat, harga bahan, dan upah berubah', () async {
      var rows = await history();
      expect(rows.single.cause, HppChangeCause.created);
      expect(rows.single.previousHpp, isNull);
      expect(rows.single.hppPerPcs, 4835);

      // Cokelat 300 g @150 + 300 g @250 → rata-rata 200/g; resep 200 g.
      await buy('cokelat', 300, 75000);
      rows = await history();
      expect(rows.first.cause, HppChangeCause.ingredientPrice);
      expect(rows.first.note, 'Cokelat');
      expect(rows.first.previousHpp, 4835);
      expect(rows.first.hppPerPcs, 5335);

      await s.business.setOwnerHourlyWage(s.businessId, 20000);
      rows = await history();
      expect(rows.first.cause, HppChangeCause.wage);
      expect(rows, hasLength(3));
    });

    test('tidak dicatat saat menerapkan data tarikan', () async {
      await withoutHppHistory(() => buy('cokelat', 300, 75000));
      expect(await history(), hasLength(1));
    });
  });

  test('simulasi kenaikan harga bahan tidak menyimpan', () async {
    // Cokelat 150/g → +50% = 225/g: 200 g × 75 ÷ 20 pcs = +750/pcs.
    final rows = await pricing.simulate(s.businessId, {
      s.ids['cokelat']!: d('225'),
    });
    final brownies = rows.single;
    expect(brownies.oldHpp, d('4835'));
    expect(brownies.newHpp, d('5585'));
    expect(brownies.newProfit, d('2415'));
    // Margin tetap 39,56%: 5.585 ÷ 0,6044 = 9.240,6 → 9.500.
    expect(brownies.suggestedPrice, 9500);
    expect((await s.product(s.brownies)).hppPerPcs, d('4835'));
    expect(await history(), hasLength(1));
  });

  group('kas', () {
    String id(String key) => '${s.businessId}-$key';

    Future<int> balance(String key) async => (await cash.balancesAt(
      s.businessId,
      DateTime(2027),
    )).firstWhere((b) => b.account.id == id(key)).balance;

    test('akun bawaan dan pemetaan cara bayar', () async {
      final accounts = await cash.watchAccounts(s.businessId).first;
      expect(accounts.map((a) => a.name), ['Tunai', 'Bank', 'QRIS/e-wallet']);
      expect(
        await cash.accountFor(s.businessId, PaymentMethod.qris),
        id('qris'),
      );
      expect(
        await cash.accountFor(s.businessId, PaymentMethod.other),
        id('tunai'),
      );

      // QRIS dipindah ke Bank: dilepas dari akun QRIS.
      await cash.saveAccount(
        s.businessId,
        id: id('bank'),
        name: 'Bank BCA',
        kind: CashAccountKind.bank,
        methods: {PaymentMethod.transfer, PaymentMethod.qris},
      );
      expect(
        await cash.accountFor(s.businessId, PaymentMethod.qris),
        id('bank'),
      );
      // Dibuat ulang tidak menambah akun.
      await cash.ensureDefaults(s.businessId);
      expect(await cash.watchAccounts(s.businessId).first, hasLength(3));
    });

    test(
      'saldo dari pembayaran, belanja, pengeluaran, dan catatan manual',
      () async {
        final order = await s.orders.createOrder(
          s.businessId,
          OrderInput(
            dueAt: DateTime(2026, 10, 25, 10),
            items: [
              OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
            ],
          ),
        );
        await s.orders.addPayment(
          order,
          amount: 30000,
          method: PaymentMethod.transfer,
          paidAt: DateTime(2026, 10, 20, 9),
        );
        final voided = await s.orders.addPayment(
          order,
          amount: 5000,
          method: PaymentMethod.cash,
          paidAt: DateTime(2026, 10, 20, 9),
        );
        await s.orders.voidPayment(voided, reason: 'Salah catat');
        await buy('tepung', 1000, 18000);
        final expenses = ExpenseRepository(s.db);
        final category =
            (await expenses.watchCategories(s.businessId).first).first;
        await expenses.addExpense(
          s.businessId,
          categoryId: category.id,
          amount: 12000,
          spentAt: DateTime(2026, 10, 20, 12),
          cashAccountId: id('bank'),
        );
        await cash.addEntry(
          s.businessId,
          kind: CashEntryKind.capitalIn,
          accountId: id('tunai'),
          amount: 100000,
          occurredAt: DateTime(2026, 10, 20, 6),
        );
        await cash.addEntry(
          s.businessId,
          kind: CashEntryKind.ownerDraw,
          accountId: id('tunai'),
          amount: 10000,
          occurredAt: DateTime(2026, 10, 20, 18),
        );
        await cash.addEntry(
          s.businessId,
          kind: CashEntryKind.transfer,
          accountId: id('tunai'),
          toAccountId: id('bank'),
          amount: 20000,
          occurredAt: DateTime(2026, 10, 20, 19),
        );

        // Tunai: 100.000 − 18.000 − 10.000 − 20.000; Bank: 30.000 − 12.000 + 20.000.
        expect(await balance('tunai'), 52000);
        expect(await balance('bank'), 38000);

        final period = await cash.period(
          s.businessId,
          DateTime(2026, 10),
          DateTime(2026, 11),
        );
        expect(period.inflow, 130000);
        expect(period.outflow, 40000);
        expect(period.total, 90000);
        expect(period.days.first.day, DateTime(2026, 10, 20));
        expect(period.days.first.inflow, 130000);
        expect(period.days.first.outflow, 40000);

        // Koreksi: uang tunai dihitung 50.000 → selisih −2.000.
        await cash.adjustTo(
          s.businessId,
          accountId: id('tunai'),
          actual: 50000,
          at: DateTime(2026, 10, 20, 20),
        );
        expect(await balance('tunai'), 50000);

        // Saldo awal Bank 5.000 per 20 Okt 10.00: pembayaran 09.00 sudah
        // termasuk saldo awal; pengeluaran dan pindahan sesudahnya dihitung.
        await cash.saveAccount(
          s.businessId,
          id: id('bank'),
          name: 'Bank',
          kind: CashAccountKind.bank,
          openingBalance: 5000,
          openingAt: DateTime(2026, 10, 20, 10),
          methods: {PaymentMethod.transfer},
        );
        expect(await balance('bank'), 13000);
      },
    );

    test('uang kembali keluar dari akun cara pengembaliannya', () async {
      final order = await s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: DateTime(2026, 10, 25, 10),
          items: [
            OrderItemInput(productId: s.brownies, qty: 2, unitPrice: 8000),
          ],
        ),
      );
      await s.orders.addPayment(
        order,
        amount: 16000,
        method: PaymentMethod.qris,
      );
      await s.orders.cancelOrder(
        order,
        reason: 'Batal',
        refund: 16000,
        refundMethod: PaymentMethod.qris,
      );
      expect(await balance('qris'), 0);
      final movements = await cash.movements(s.businessId);
      expect(movements.first.source, CashSource.refund);
      expect(movements.first.accountId, id('qris'));
    });
  });

  test('kolom akun kas lama kosong dianggap Tunai', () async {
    await buy('tepung', 1000, 18000);
    await (s.db.update(s.db.purchases))
        .write(const PurchasesCompanion(cashAccountId: Value(null)));
    final movements = await cash.movements(s.businessId);
    expect(movements.single.accountId, '${s.businessId}-tunai');
  });
}
