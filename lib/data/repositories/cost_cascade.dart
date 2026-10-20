import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../../domain/stock/product_ledger.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';

/// Rantai hitung ulang setelah koreksi harga bahan (FR-9.3, FR-9.5):
/// nilai mutasi bahan → biaya produksi → HPP mutasi stok menu jadi → HPP
/// rata-rata stok menu dan HPP terjual dari stok.

/// Hitung ulang stok menu jadi dari buku mutasinya (FR-4.5).
Future<void> recomputeProductStock(AppDatabase db, String productId) async {
  final rows = await (db.select(
    db.productStockMovements,
  )..where((t) => t.productId.equals(productId))).get();
  rows.sort((a, b) {
    final byTime = a.occurredAt.compareTo(b.occurredAt);
    if (byTime != 0) return byTime;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
  });
  final result = replayProductLedger([
    for (final r in rows)
      ProductLedgerMovement(
        id: r.id,
        type: r.type,
        qty: dec(r.qty),
        unitCost: dec(r.unitCost),
        reversalOfId: r.reversalOfId,
      ),
  ]);
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final res = result.rows[i];
    final unitCost = dbl(res.unitCost);
    final balance = dbl(res.balanceAfter);
    final avg = dbl(res.avgCostAfter);
    final changed = res.cancelled
        ? row.balanceAfter != balance || row.avgCostAfter != avg
        : row.unitCost != unitCost ||
              row.value != res.value ||
              row.balanceAfter != balance ||
              row.avgCostAfter != avg;
    if (!changed) continue;
    await (db.update(
      db.productStockMovements,
    )..where((t) => t.id.equals(row.id))).write(
      ProductStockMovementsCompanion(
        unitCost: res.cancelled ? const Value.absent() : Value(unitCost),
        value: res.cancelled ? const Value.absent() : Value(res.value),
        balanceAfter: Value(balance),
        avgCostAfter: Value(avg),
      ),
    );
  }
  await (db.update(db.products)..where((t) => t.id.equals(productId))).write(
    ProductsCompanion(
      currentStock: Value(dbl(result.stock)),
      stockUnitCost: Value(dbl(result.avgUnitCost)),
      updatedAt: Value(DateTime.now().toUtc()),
    ),
  );
}

/// Biaya bahan produksi diambil ulang dari nilai mutasi bahannya; jika
/// berubah, HPP batch dan mutasi PRODUCTION di stok menu jadi ikut
/// diperbarui lalu stok menu diputar ulang.
Future<void> refreshProductionCosts(
  AppDatabase db,
  Iterable<String> productionIds,
) async {
  final productIds = <String>{};
  for (final id in productionIds.toSet()) {
    final production = await (db.select(
      db.productions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (production == null || production.voidedAt != null) continue;
    final usage =
        await (db.select(db.stockMovements)..where(
              (t) =>
                  t.refType.equals('production') &
                  t.refId.equals(id) &
                  t.reversalOfId.isNull(),
            ))
            .get();
    final material = usage.fold(0, (sum, m) => sum - m.value);
    if (material == production.materialCost) continue;
    final output = dec(production.outputQty);
    if (output <= Decimal.zero) continue;
    final hpp = divide(rupiah(material + production.otherCost), output);
    await (db.update(db.productions)..where((t) => t.id.equals(id))).write(
      ProductionsCompanion(
        materialCost: Value(material),
        hppPerPcs: Value(dbl(hpp)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    final receipts =
        await (db.select(db.productStockMovements)..where(
              (t) =>
                  t.refType.equals('production') &
                  t.refId.equals(id) &
                  t.reversalOfId.isNull(),
            ))
            .get();
    for (final r in receipts) {
      await (db.update(
        db.productStockMovements,
      )..where((t) => t.id.equals(r.id))).write(
        ProductStockMovementsCompanion(
          unitCost: Value(dbl(hpp)),
          value: Value(toRupiah(dec(r.qty) * hpp)),
        ),
      );
      productIds.add(r.productId);
    }
  }
  for (final productId in productIds) {
    await recomputeProductStock(db, productId);
  }
}
