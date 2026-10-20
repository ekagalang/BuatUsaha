import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/repositories/order_repository.dart';
import 'package:hpp_app/data/repositories/purchase_preview.dart';
import 'package:hpp_app/data/repositories/stock_repository.dart';

import '../support/seed.dart';

/// FR-9.5: koreksi harga bahan menghitung ulang biaya produksi dan stok menu
/// jadi; pesanan lama yang terdampak ditampilkan dan bisa dihitung ulang.
void main() {
  late Seed s;

  setUp(() async => s = await Seed.create());
  tearDown(() => s.close());

  PurchaseInput tepung(int price, {int day = 10}) => PurchaseInput(
    purchasedAt: DateTime.utc(2026, 10, day),
    lines: [
      PurchaseLineInput(
        ingredientId: s.ids['tepung']!,
        qty: d('1'),
        unitName: 'kg',
        factorToBase: d('1000'),
        totalPrice: price,
      ),
    ],
  );

  Future<String> sell(String productId, {required DateTime at}) =>
      s.orders.recordDirectSale(
        s.businessId,
        OrderInput(
          dueAt: at,
          items: [
            OrderItemInput(productId: productId, qty: 10, unitPrice: 8000),
          ],
        ),
      );

  test('salah ketik Rp140.000 lalu dikoreksi Rp14.000 (kriteria PRD 5.9)', () async {
    // Stok awal 1.000 g @ Rp12 + belanja salah 1 kg Rp140.000 → Rp76/g.
    final wrong = await s.stock.recordPurchase(s.businessId, tepung(140000));
    final production = await s.products.recordProduction(
      s.brownies,
      batchQty: Decimal.one,
      at: DateTime.utc(2026, 10, 15),
    );
    // Bahan 64.000 + 250 g × (76 − 12) = 80.000 → (80.000 + 27.500) / 20 + 260.
    expect((await s.product(s.brownies)).product.stockUnitCost, 5635);
    final order = await sell(s.brownies, at: DateTime.utc(2026, 10, 16));
    expect(
      (await s.orders.loadOrder(order)).lines.single.item.hppPerPcsSnapshot,
      5635,
    );
    expect(await s.orders.costCorrections(s.businessId), isEmpty);

    await s.stock.replacePurchase(wrong, tepung(14000));

    // Rp13/g → bahan 64.250 → HPP (64.250 + 27.500) / 20 + 260 = 4.847,5.
    final made = (await s.products.watchProductions(s.brownies).first)
        .firstWhere((p) => p.id == production);
    expect(made.materialCost, 64250);
    expect(made.hppPerPcs, 4847.5);
    final menu = await s.product(s.brownies);
    expect(menu.product.stockUnitCost, 4847.5);
    expect(menu.stockValue, 48475);

    final corrections = await s.orders.costCorrections(s.businessId);
    final c = corrections.single;
    expect(c.view.order.id, order);
    expect(c.items.single.oldHpp, d('5635'));
    expect(c.items.single.newHpp, d('4847.5'));
    expect(c.profitDelta, 7875);

    await s.orders.applyCostCorrection(order);
    expect(
      (await s.orders.loadOrder(order)).lines.single.item.hppPerPcsSnapshot,
      4847.5,
    );
    expect(await s.orders.costCorrections(s.businessId), isEmpty);
  });

  test(
    'pesanan pre-order: selisih harga bahan saat dicatat vs sesudah koreksi',
    () async {
      final po = await s.products.createProduct(
        s.businessId,
        s.browniesInput(mode: StockDeductMode.onComplete, name: 'Brownies PO'),
      );
      final wrong = await s.stock.recordPurchase(s.businessId, tepung(140000));
      expect((await s.product(po)).hppPerPcs, d('5635'));
      final order = await sell(po, at: DateTime.utc(2026, 10, 16));

      await s.stock.replacePurchase(wrong, tepung(14000));

      // 10 pcs = 125 g tepung; (13 − 76) × 125 = −7.875 → −787,5 per pcs.
      final c = (await s.orders.costCorrections(s.businessId)).single;
      expect(c.view.order.id, order);
      expect(c.items.single.oldHpp, d('5635'));
      expect(c.items.single.newHpp, d('4847.5'));
      expect(c.profitDelta, 7875);
    },
  );

  test('pratinjau ubah belanja menampilkan dampak tanpa menyimpan', () async {
    final wrong = await s.stock.recordPurchase(s.businessId, tepung(140000));
    await s.products.recordProduction(
      s.brownies,
      batchQty: Decimal.one,
      at: DateTime.utc(2026, 10, 15),
    );
    await sell(s.brownies, at: DateTime.utc(2026, 10, 16));

    final preview = await PurchasePreviewer(
      s.db,
      s.stock,
      s.orders,
    ).preview(s.businessId, wrong, tepung(14000));
    final avg = preview.ingredients.single;
    expect(avg.name, 'Tepung');
    expect(avg.before, d('76'));
    expect(avg.after, d('13'));
    final menu = preview.menus.single;
    expect(menu.before, d('5635'));
    expect(menu.after, d('4847.5'));
    expect(preview.ordersAffected, 1);

    // Tidak ada yang tersimpan.
    final tepungNow = await s.stock.watchIngredient(s.ids['tepung']!).first;
    expect(tepungNow.avgUnitCost, d('76'));
    expect(tepungNow.stock, d('1750'));
    expect(await s.orders.costCorrections(s.businessId), isEmpty);
  });

  test(
    'pesanan yang dikoreksi atau tanpa perubahan harga tidak muncul',
    () async {
      await s.products.recordProduction(
        s.brownies,
        batchQty: Decimal.one,
        at: DateTime.utc(2026, 10, 15),
      );
      final order = await sell(s.brownies, at: DateTime.utc(2026, 10, 16));
      // Belanja sesudah pesanan selesai tidak mengubah HPP pesanan itu.
      await s.stock.recordPurchase(s.businessId, tepung(14000, day: 20));
      expect(await s.orders.costCorrections(s.businessId), isEmpty);

      // Belanja bertanggal mundur mengubahnya; pesanan yang dikoreksi tidak.
      await s.stock.recordPurchase(s.businessId, tepung(14000, day: 12));
      expect(await s.orders.costCorrections(s.businessId), hasLength(1));
      await s.orders.voidCompletedOrder(order, reason: 'tes');
      expect(await s.orders.costCorrections(s.businessId), isEmpty);
    },
  );
}
