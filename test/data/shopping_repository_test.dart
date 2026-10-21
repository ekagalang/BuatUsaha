import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/shopping_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/domain/stock/units.dart';

import '../support/seed.dart';

/// Rabu, 22 Okt 2026 pukul 08.00.
final _now = DateTime(2026, 10, 22, 8);

void main() {
  late Seed s;
  late ShoppingRepository repo;

  setUp(() async {
    s = await Seed.create();
    repo = ShoppingRepository(s.db, s.orders);
  });
  tearDown(() => s.close());

  Future<String> order(int qty, DateTime due, {String? productId}) =>
      s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: due,
          items: [
            OrderItemInput(
              productId: productId ?? s.brownies,
              qty: qty,
              unitPrice: 8000,
            ),
          ],
        ),
      );

  Future<String> buyCokelat(int grams) => s.stock.recordPurchase(
    s.businessId,
    PurchaseInput(
      purchasedAt: DateTime(2026, 10, 22, 7),
      lines: [
        PurchaseLineInput(
          ingredientId: s.ids['cokelat']!,
          qty: Decimal.fromInt(grams),
          unitName: 'g',
          factorToBase: Decimal.one,
          totalPrice: grams * 150,
        ),
      ],
    ),
  );

  ShoppingSuggestion? find(ShoppingPlan plan, String key) =>
      plan.items.where((i) => i.ingredient.id == s.ids[key]).firstOrNull;

  test(
    'kekurangan bahan untuk pesanan 3 hari, dibulatkan ke satuan beli',
    () async {
      // 40 brownies = 2 resep → cokelat 400 g, stok 300 g.
      await order(40, DateTime(2026, 10, 23, 13));
      var plan = await repo.plan(s.businessId, 3, now: _now);
      var cokelat = find(plan, 'cokelat')!;
      expect(cokelat.requiredQty, d('400'));
      expect(cokelat.shortage, d('100'));
      expect(cokelat.unit.name, 'g');
      expect(cokelat.unitQty, d('100'));
      expect(cokelat.forOrders, isTrue);
      expect(cokelat.belowMinimum, isFalse);
      expect(cokelat.estimatedCost, 15000);
      // Telur 8 butir, stok 10: cukup.
      expect(find(plan, 'telur'), isNull);
      expect(plan.orderCount, 1);
      expect(plan.until, DateTime(2026, 10, 24));

      await s.stock.addCustomUnit(
        s.ids['cokelat']!,
        unitName: 'pack',
        factorToBase: d('200'),
      );
      plan = await repo.plan(s.businessId, 3, now: _now);
      cokelat = find(plan, 'cokelat')!;
      expect(cokelat.unit.name, 'pack');
      expect(cokelat.unitQty, d('1'));
      expect(cokelat.baseQty, d('200'));
      expect(cokelat.estimatedCost, 30000);
    },
  );

  test('rentang menentukan pesanan yang dihitung', () async {
    await order(40, DateTime(2026, 10, 27, 10));
    expect((await repo.plan(s.businessId, 3, now: _now)).items, isEmpty);
    final week = await repo.plan(s.businessId, 7, now: _now);
    expect(find(week, 'cokelat'), isNotNull);
    expect(week.until, DateTime(2026, 10, 28));
  });

  test('stok jaga dan stok minimum ikut dihitung', () async {
    // Stok jaga 40 pcs tanpa pesanan → 2 resep → cokelat kurang 100 g.
    await (s.db.update(s.db.products)..where((t) => t.id.equals(s.brownies)))
        .write(const ProductsCompanion(safetyStock: Value(40)));
    // Mentega 1.000 g, butuh 400 g, minimum 800 g → kurang 200 g.
    await s.stock.updateIngredient(s.ids['mentega']!, minStock: d('800'));
    final plan = await repo.plan(s.businessId, 3, now: _now);
    expect(find(plan, 'cokelat')!.forOrders, isTrue);
    final mentega = find(plan, 'mentega')!;
    expect(mentega.shortage, d('200'));
    expect(mentega.forOrders, isFalse);
    expect(mentega.belowMinimum, isTrue);
    expect(plan.orderCount, 0);
  });

  test(
    'pre-order: yang sudah diproduksi untuk pesanan tidak dihitung lagi',
    () async {
      final cookies = await s.products.createProduct(
        s.businessId,
        s.browniesInput(
          name: 'Cookies pre-order',
          mode: StockDeductMode.onComplete,
        ),
      );
      final id = await order(
        40,
        DateTime(2026, 10, 23, 13),
        productId: cookies,
      );
      expect(
        find(await repo.plan(s.businessId, 3, now: _now), 'cokelat'),
        isNotNull,
      );
      await buyCokelat(200);
      await s.products.recordProduction(
        cookies,
        batchQty: d('2'),
        orderId: id,
        at: DateTime(2026, 10, 22, 7),
      );
      final after = await repo.plan(s.businessId, 3, now: _now);
      expect(after.items.where((i) => i.forOrders), isEmpty);
    },
  );

  test(
    'hitung ulang mempertahankan item sendiri, dicentang, dan tercatat',
    () async {
      final first = await order(40, DateTime(2026, 10, 23, 13));
      await s.stock.updateIngredient(s.ids['mentega']!, minStock: d('1200'));
      final list = await repo.activeList(s.businessId);
      await repo.recalculate(list.id, now: _now);
      var view = await repo.view(list.id);
      expect(view.lines.map((l) => l.item.name), ['Cokelat', 'Mentega']);
      expect(view.list.orderCount, 1);
      expect(view.until, DateTime(2026, 10, 24));

      final cokelat = view.lines.first;
      final mentega = view.lines.last;
      await repo.setChecked(cokelat.item.id, checked: true);
      await repo.updateItem(
        mentega.item.id,
        d('3'),
        UnitOption(name: 'g', factorToBase: Decimal.one),
      );
      await repo.addOther(list.id, 'Plastik kemasan', qty: 2, unitName: 'pak');

      // Pesanan dibatalkan dan minimum dihapus: tidak ada lagi yang otomatis.
      await s.orders.cancelOrder(first, reason: 'Batal');
      await s.stock.updateIngredient(s.ids['mentega']!, minStock: d('0'));
      await repo.recalculate(list.id, now: _now);
      view = await repo.view(list.id);
      expect(view.lines.map((l) => l.item.name), [
        'Cokelat',
        'Mentega',
        'Plastik kemasan',
      ]);
      expect(view.lines[1].item.qty, 3);
      expect(view.lines[1].item.source, ShoppingItemSource.manual);
      expect(view.otherCount, 1);
      expect(view.toRecord.map((l) => l.item.name), ['Cokelat']);
    },
  );

  test(
    'item otomatis yang tidak dibutuhkan lagi dihapus saat hitung ulang',
    () async {
      final id = await order(40, DateTime(2026, 10, 23, 13));
      final list = await repo.activeList(s.businessId);
      await repo.recalculate(list.id, now: _now);
      expect((await repo.view(list.id)).lines, hasLength(1));
      await s.orders.cancelOrder(id, reason: 'Batal');
      await repo.recalculate(list.id, now: _now);
      expect((await repo.view(list.id)).lines, isEmpty);
    },
  );

  test(
    'catat jadi belanja, lalu selesai belanja memulai daftar baru',
    () async {
      await order(40, DateTime(2026, 10, 23, 13));
      final list = await repo.activeList(s.businessId);
      await repo.recalculate(list.id, now: _now);
      final line = (await repo.view(list.id)).lines.single;
      await repo.setChecked(line.item.id, checked: true);
      expect((await repo.linesToRecord(list.id)), hasLength(1));

      final purchase = await buyCokelat(200);
      await repo.markRecorded([line.item.id], purchase);
      final view = await repo.view(list.id);
      expect(view.toRecord, isEmpty);
      expect(view.done.single.recorded, isTrue);
      await expectLater(
        repo.setChecked(line.item.id, checked: false),
        throwsStateError,
      );

      await repo.finish(list.id);
      final next = await repo.activeList(s.businessId);
      expect(next.id, isNot(list.id));
    },
  );

  test('tambah bahan sendiri memakai satuan beli bawaan', () async {
    await s.stock.addCustomUnit(
      s.ids['gula']!,
      unitName: 'kg',
      factorToBase: d('1000'),
    );
    final list = await repo.activeList(s.businessId);
    await repo.addIngredient(list.id, s.ids['gula']!);
    final line = (await repo.view(list.id)).lines.single;
    expect(line.item.unitName, 'kg');
    expect(line.item.estimatedCost, 15000);
    expect(line.item.source, ShoppingItemSource.manual);
    expect(line.ingredient!.name, 'Gula');
  });
}
