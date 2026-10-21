import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';

/// Satu bahan di resep beserta data bahannya.
class RecipeLineView {
  const RecipeLineView({required this.item, required this.ingredient});

  final RecipeItem item;
  final Ingredient ingredient;

  RecipeLine get line => RecipeLine(
    ingredientId: ingredient.id,
    qtyPerBatch: dec(item.qtyBase),
    unitCost: ingredient.avgUnitCost == null
        ? null
        : dec(ingredient.avgUnitCost!),
    isEstimate: ingredient.priceIsEstimate,
  );
}

/// Semua angka biaya satu menu, dihitung dari data terkini.
class ProductCosting {
  const ProductCosting({
    required this.product,
    required this.lines,
    required this.costs,
    required this.ownerHourlyWage,
    required this.hpp,
    required this.wageMissing,
  });

  final Product product;
  final List<RecipeLineView> lines;
  final List<ProductCost> costs;
  final int? ownerHourlyWage;
  final HppBreakdown hpp;

  /// Ada jam kerja pemilik tapi upah per jam belum diisi di pengaturan.
  final bool wageMissing;

  HppStatus get status {
    if (lines.isEmpty || wageMissing) return HppStatus.incomplete;
    return hpp.status;
  }

  /// Nominal biaya lain; upah pemilik = jam × upah per jam terkini.
  int amountOf(ProductCost cost) {
    final hours = cost.laborHours;
    if (hours == null) return cost.amount;
    final wage = ownerHourlyWage;
    return wage == null ? 0 : laborCost(hours: dec(hours), hourlyWage: wage);
  }
}

Future<ProductCosting> loadProductCosting(
  AppDatabase db,
  Product product,
) async {
  final business = await (db.select(
    db.businesses,
  )..where((t) => t.id.equals(product.businessId))).getSingle();
  final rows =
      await (db.select(db.recipeItems).join([
              innerJoin(
                db.ingredients,
                db.ingredients.id.equalsExp(db.recipeItems.ingredientId),
              ),
            ])
            ..where(db.recipeItems.productId.equals(product.id))
            ..orderBy([OrderingTerm.asc(db.recipeItems.createdAt)]))
          .get();
  final lines = [
    for (final row in rows)
      RecipeLineView(
        item: row.readTable(db.recipeItems),
        ingredient: row.readTable(db.ingredients),
      ),
  ];
  final costs =
      await (db.select(db.productCosts)
            ..where((t) => t.productId.equals(product.id))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
  final wage = business.ownerHourlyWage;
  final wageMissing = wage == null && costs.any((c) => (c.laborHours ?? 0) > 0);
  final partial = ProductCosting(
    product: product,
    lines: lines,
    costs: costs,
    ownerHourlyWage: wage,
    hpp: calculateHpp(lines: const [], yieldQty: Decimal.one),
    wageMissing: wageMissing,
  );
  final hpp = calculateHpp(
    lines: [for (final l in lines) l.line],
    otherCosts: [
      for (final c in costs)
        OtherCost(name: c.name, amount: partial.amountOf(c), basis: c.basis),
    ],
    yieldQty: product.yieldQty > 0 ? dec(product.yieldQty) : Decimal.one,
  );
  return ProductCosting(
    product: product,
    lines: lines,
    costs: costs,
    ownerHourlyWage: wage,
    hpp: hpp,
    wageMissing: wageMissing,
  );
}

const _quietHistory = #buatUsahaQuietHppHistory;

/// Jalankan [body] tanpa mencatat riwayat HPP, mis. saat menerapkan data
/// tarikan: riwayatnya sudah dicatat HP yang mengubah (FR-14.3).
Future<T> withoutHppHistory<T>(Future<T> Function() body) =>
    runZoned(body, zoneValues: {_quietHistory: true});

/// Perbarui cache HPP di `products` dan nominal upah pemilik (FR-2.4). Bila
/// HPP per pcs berubah dan [cause] diisi, perubahannya dicatat (FR-14.3).
Future<ProductCosting> refreshProductHpp(
  AppDatabase db,
  String productId, {
  HppChangeCause? cause,
  String? note,
}) async {
  final product = await (db.select(
    db.products,
  )..where((t) => t.id.equals(productId))).getSingle();
  final costing = await loadProductCosting(db, product);
  for (final cost in costing.costs) {
    final amount = costing.amountOf(cost);
    if (cost.laborHours != null && cost.amount != amount) {
      await (db.update(db.productCosts)..where((t) => t.id.equals(cost.id)))
          .write(ProductCostsCompanion(amount: Value(amount)));
    }
  }
  final hpp = dbl(costing.hpp.hppPerPcs);
  if (product.hppPerPcs != hpp || product.hppStatus != costing.status) {
    await (db.update(db.products)..where((t) => t.id.equals(productId))).write(
      ProductsCompanion(
        hppPerPcs: Value(hpp),
        hppStatus: Value(costing.status),
        hppUpdatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
  if (cause != null &&
      product.hppPerPcs != hpp &&
      Zone.current[_quietHistory] != true) {
    await db
        .into(db.productHppHistory)
        .insert(
          ProductHppHistoryCompanion.insert(
            productId: productId,
            hppPerPcs: hpp,
            previousHpp: Value(
              cause == HppChangeCause.created ? null : product.hppPerPcs,
            ),
            cause: cause,
            note: Value(note),
            changedAt: DateTime.now().toUtc(),
          ),
        );
  }
  return costing;
}

/// Harga rata-rata bahan berubah → HPP semua menu yang memakainya dihitung
/// ulang.
Future<void> refreshHppForIngredient(
  AppDatabase db,
  String ingredientId,
) async {
  final items = await (db.select(
    db.recipeItems,
  )..where((t) => t.ingredientId.equals(ingredientId))).get();
  if (items.isEmpty) return;
  final ingredient = await (db.select(
    db.ingredients,
  )..where((t) => t.id.equals(ingredientId))).getSingleOrNull();
  for (final productId in {for (final i in items) i.productId}) {
    await refreshProductHpp(
      db,
      productId,
      cause: HppChangeCause.ingredientPrice,
      note: ingredient?.name,
    );
  }
}

/// Upah per jam berubah → semua menu usaha dihitung ulang.
Future<void> refreshAllHpp(
  AppDatabase db,
  String businessId, {
  HppChangeCause? cause,
}) async {
  final products = await (db.select(
    db.products,
  )..where((t) => t.businessId.equals(businessId))).get();
  for (final p in products) {
    await refreshProductHpp(db, p.id, cause: cause);
  }
}
