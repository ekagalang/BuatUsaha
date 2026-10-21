import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'order_repository.dart';
import 'stock_repository.dart';

class AvgChange {
  const AvgChange({
    required this.name,
    required this.unit,
    required this.before,
    required this.after,
  });

  final String name;
  final String unit;
  final Decimal? before;
  final Decimal? after;
}

class HppChange {
  const HppChange({
    required this.name,
    required this.before,
    required this.after,
  });

  final String name;
  final Decimal before;
  final Decimal after;
}

/// Dampak mengubah belanja: harga rata-rata bahan, HPP menu, dan pesanan
/// selesai yang ikut terdampak (FR-9.2, FR-9.5).
class PurchaseEditPreview {
  const PurchaseEditPreview({
    required this.ingredients,
    required this.menus,
    required this.ordersAffected,
  });

  final List<AvgChange> ingredients;
  final List<HppChange> menus;
  final int ordersAffected;
}

class _DryRun implements Exception {
  const _DryRun();
}

/// Menjalankan penggantian belanja di dalam transaksi lalu membatalkannya,
/// supaya dampaknya bisa ditampilkan sebelum disimpan.
class PurchasePreviewer {
  PurchasePreviewer(this._db, this._stock, this._orders);

  final AppDatabase _db;
  final StockRepository _stock;
  final OrderRepository _orders;

  Future<PurchaseEditPreview> preview(
    String businessId,
    String purchaseId,
    PurchaseInput input,
  ) async {
    final oldItems = await (_db.select(
      _db.purchaseItems,
    )..where((t) => t.purchaseId.equals(purchaseId))).get();
    final ingredientIds = {
      for (final i in oldItems) i.ingredientId,
      for (final l in input.lines) l.ingredientId,
    };
    final before = await _ingredients(ingredientIds);
    final productsBefore = {
      for (final p in await _products(businessId)) p.id: p,
    };
    PurchaseEditPreview? result;
    try {
      await _db.transaction(() async {
        await _stock.replacePurchase(purchaseId, input, reason: 'Pratinjau');
        final after = {
          for (final i in await _ingredients(ingredientIds)) i.id: i,
        };
        final menus = <HppChange>[];
        for (final p in await _products(businessId)) {
          final old = productsBefore[p.id];
          if (old == null || old.hppPerPcs == p.hppPerPcs) continue;
          menus.add(
            HppChange(
              name: p.name,
              before: dec(old.hppPerPcs),
              after: dec(p.hppPerPcs),
            ),
          );
        }
        final corrections = await _orders.costCorrections(businessId);
        result = PurchaseEditPreview(
          ingredients: [
            for (final b in before)
              AvgChange(
                name: b.name,
                unit: b.baseUnit.code,
                before: b.avgUnitCost == null ? null : dec(b.avgUnitCost!),
                after: after[b.id]?.avgUnitCost == null
                    ? null
                    : dec(after[b.id]!.avgUnitCost!),
              ),
          ],
          menus: menus..sort((a, b) => a.name.compareTo(b.name)),
          ordersAffected: corrections.length,
        );
        throw const _DryRun();
      });
    } on _DryRun {
      // Dibatalkan dengan sengaja; tidak ada yang tersimpan.
    }
    return result!;
  }

  Future<List<Ingredient>> _ingredients(Set<String> ids) =>
      (_db.select(_db.ingredients)
            ..where((t) => t.id.isIn(ids))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<Product>> _products(String businessId) => (_db.select(
    _db.products,
  )..where((t) => t.businessId.equals(businessId))).get();
}
