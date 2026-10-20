import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../../domain/stock/product_ledger.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'hpp_refresher.dart';
import 'stock_repository.dart';

DateTime _now() => DateTime.now().toUtc();

/// Stok bahan tidak cukup untuk produksi dan usaha tidak mengizinkan stok
/// minus.
class InsufficientStockException implements Exception {
  const InsufficientStockException(this.ingredientNames);

  final List<String> ingredientNames;

  @override
  String toString() =>
      'Stok ${ingredientNames.join(', ')} tidak cukup. Catat belanja dulu.';
}

class RecipeInput {
  const RecipeInput({required this.ingredientId, required this.qtyBase});

  final String ingredientId;

  /// Takaran per 1 resep, satuan dasar bahan.
  final Decimal qtyBase;
}

class CostInput {
  const CostInput({
    required this.name,
    required this.costType,
    required this.basis,
    this.amount = 0,
    this.laborHours,
  });

  final String name;
  final CostType costType;
  final CostBasis basis;
  final int amount;

  /// Upah pemilik: jam kerja per resep; nominalnya dari upah per jam usaha.
  final Decimal? laborHours;
}

class ProductInput {
  const ProductInput({
    required this.name,
    required this.sellingPrice,
    required this.yieldQty,
    required this.recipe,
    this.costs = const [],
    this.category,
    this.shelfLifeDays,
    this.stockDeductMode,
    this.targetMarkupPct,
  });

  final String name;
  final int sellingPrice;
  final Decimal yieldQty;
  final List<RecipeInput> recipe;
  final List<CostInput> costs;
  final String? category;
  final int? shelfLifeDays;

  /// `null` = ikut mode stok bawaan usaha.
  final StockDeductMode? stockDeductMode;
  final Decimal? targetMarkupPct;
}

/// Menu beserta HPP, harga, kapasitas, dan stok produk jadinya.
class ProductView {
  const ProductView({required this.costing, required this.business});

  final ProductCosting costing;
  final Business business;

  Product get product => costing.product;
  HppBreakdown get hpp => costing.hpp;
  HppStatus get status => costing.status;
  Decimal get hppPerPcs => costing.hpp.hppPerPcs;

  StockDeductMode get mode =>
      product.stockDeductMode ?? business.stockDeductMode;
  bool get isReadyStock => mode == StockDeductMode.onProduction;

  Decimal get markupTarget => product.targetMarkupPct == null
      ? dec(business.defaultMarkupPct)
      : dec(product.targetMarkupPct!);

  bool get _hasHpp => status != HppStatus.incomplete;

  /// `null` jika HPP belum lengkap atau harga jual 0.
  Decimal? get marginPct => _hasHpp && product.sellingPrice > 0
      ? actualMarginPct(
          sellingPrice: product.sellingPrice,
          hppPerPcs: hppPerPcs,
        )
      : null;

  Decimal? get profitPerPcs =>
      _hasHpp ? rupiah(product.sellingPrice) - hppPerPcs : null;

  PriceWarning? get warning => _hasHpp
      ? priceWarning(
          sellingPrice: product.sellingPrice,
          hppPerPcs: hppPerPcs,
          targetMarkupPct: markupTarget,
        )
      : null;

  /// Saran harga tidak ditampilkan selama HPP belum lengkap (FR-2.8).
  int? get suggestedByMarkup => _hasHpp
      ? suggestPriceByMarkup(
          hppPerPcs: hppPerPcs,
          markupPct: markupTarget,
          rounding: business.priceRounding,
        )
      : null;

  int? suggestedByMargin(Decimal marginPct) => _hasHpp
      ? suggestPriceByMargin(
          hppPerPcs: hppPerPcs,
          marginPct: marginPct,
          rounding: business.priceRounding,
        )
      : null;

  List<RecipeLine> get _lines => [for (final l in costing.lines) l.line];

  Map<String, Decimal> get _stock => {
    for (final l in costing.lines)
      l.ingredient.id: dec(l.ingredient.currentStock),
  };

  /// `null` jika resep belum punya bahan.
  CapacityResult? get capacity {
    final lines = _lines.where((l) => l.qtyPerBatch > Decimal.zero).toList();
    if (lines.isEmpty || product.yieldQty <= 0) return null;
    return calculateCapacity(
      lines: lines,
      stock: _stock,
      yieldQty: dec(product.yieldQty),
    );
  }

  List<Shortage> shortagesFor(int targetPcs) => product.yieldQty <= 0
      ? const []
      : calculateShortages(
          lines: _lines,
          stock: _stock,
          yieldQty: dec(product.yieldQty),
          targetPcs: targetPcs,
        );

  Decimal get stock => dec(product.currentStock);

  int get stockValue => totalStockValue([
    StockValueLine(
      ingredientId: product.id,
      qty: stock,
      avgUnitCost: dec(product.stockUnitCost),
    ),
  ]);

  String? ingredientName(String id) {
    for (final l in costing.lines) {
      if (l.ingredient.id == id) return l.ingredient.name;
    }
    return null;
  }
}

/// Menu, resep, HPP, produksi, dan stok produk jadi (FR-2.x, FR-3.x, FR-4.x).
class ProductRepository {
  ProductRepository(this._db, this._stock);

  final AppDatabase _db;
  final StockRepository _stock;

  // ------------------------------------------------------------- Menu

  Future<String> createProduct(String businessId, ProductInput input) {
    _validate(input);
    return _db.transaction(() async {
      final product = await _db
          .into(_db.products)
          .insertReturning(
            ProductsCompanion.insert(
              businessId: businessId,
              name: input.name.trim(),
              sellingPrice: input.sellingPrice,
              yieldQty: dbl(input.yieldQty),
              category: Value(input.category),
              shelfLifeDays: Value(input.shelfLifeDays),
              stockDeductMode: Value(input.stockDeductMode),
              targetMarkupPct: Value(
                input.targetMarkupPct == null
                    ? null
                    : dbl(input.targetMarkupPct!),
              ),
            ),
          );
      await _writeChildren(product.id, input);
      await refreshProductHpp(_db, product.id);
      return product.id;
    });
  }

  Future<void> updateProduct(String id, ProductInput input) {
    _validate(input);
    return _db.transaction(() async {
      await (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(
          name: Value(input.name.trim()),
          sellingPrice: Value(input.sellingPrice),
          yieldQty: Value(dbl(input.yieldQty)),
          category: Value(input.category),
          shelfLifeDays: Value(input.shelfLifeDays),
          stockDeductMode: Value(input.stockDeductMode),
          targetMarkupPct: Value(
            input.targetMarkupPct == null ? null : dbl(input.targetMarkupPct!),
          ),
          updatedAt: Value(_now()),
        ),
      );
      await (_db.delete(
        _db.recipeItems,
      )..where((t) => t.productId.equals(id))).go();
      await (_db.delete(
        _db.productCosts,
      )..where((t) => t.productId.equals(id))).go();
      await _writeChildren(id, input);
      await refreshProductHpp(_db, id);
    });
  }

  Future<void> setSellingPrice(String id, int price) =>
      (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(sellingPrice: Value(price), updatedAt: Value(_now())),
      );

  Future<ProductInput> inputOf(String id) async {
    final product = await _product(id);
    final costing = await loadProductCosting(_db, product);
    return ProductInput(
      name: product.name,
      sellingPrice: product.sellingPrice,
      yieldQty: dec(product.yieldQty),
      category: product.category,
      shelfLifeDays: product.shelfLifeDays,
      stockDeductMode: product.stockDeductMode,
      targetMarkupPct: product.targetMarkupPct == null
          ? null
          : dec(product.targetMarkupPct!),
      recipe: [
        for (final l in costing.lines)
          RecipeInput(
            ingredientId: l.ingredient.id,
            qtyBase: dec(l.item.qtyBase),
          ),
      ],
      costs: [
        for (final c in costing.costs)
          CostInput(
            name: c.name,
            costType: c.costType,
            basis: c.basis,
            amount: c.amount,
            laborHours: c.laborHours == null ? null : dec(c.laborHours!),
          ),
      ],
    );
  }

  Stream<List<ProductView>> watchProducts(String businessId) =>
      _watch(() async {
        final business = await _business(businessId);
        final products =
            await (_db.select(_db.products)
                  ..where(
                    (t) =>
                        t.businessId.equals(businessId) & t.deletedAt.isNull(),
                  )
                  ..orderBy([(t) => OrderingTerm.asc(t.name)]))
                .get();
        return [
          for (final p in products)
            ProductView(
              costing: await loadProductCosting(_db, p),
              business: business,
            ),
        ];
      });

  Stream<ProductView> watchProduct(String id) => _watch(() async {
    final product = await _product(id);
    return ProductView(
      costing: await loadProductCosting(_db, product),
      business: await _business(product.businessId),
    );
  });

  // --------------------------------------------------------- Produksi

  /// Catat produksi (FR-4.1, FR-4.2): bahan dipotong sesuai resep ×
  /// [batchQty] (atau [actualUsage] per bahan), HPP batch disimpan, dan untuk
  /// menu ready stock hasilnya masuk stok produk jadi (FR-4.5).
  Future<String> recordProduction(
    String productId, {
    required Decimal batchQty,
    Map<String, Decimal> actualUsage = const {},
    String? orderId,
    DateTime? at,
    String? note,
  }) {
    if (batchQty <= Decimal.zero) {
      throw ArgumentError.value(batchQty, 'batchQty', 'harus > 0');
    }
    final when = (at ?? _now()).toUtc();
    return _db.transaction(() async {
      final product = await _product(productId);
      final costing = await loadProductCosting(_db, product);
      if (costing.lines.isEmpty) {
        throw StateError('Resep menu ini belum punya bahan.');
      }
      final output = batchQty * dec(product.yieldQty);
      final usage = {
        for (final l in costing.lines)
          l.ingredient.id:
              actualUsage[l.ingredient.id] ?? dec(l.item.qtyBase) * batchQty,
      };
      final business = await _business(product.businessId);
      if (!business.allowNegativeStock) {
        final short = [
          for (final l in costing.lines)
            if (usage[l.ingredient.id]! > dec(l.ingredient.currentStock))
              l.ingredient.name,
        ];
        if (short.isNotEmpty) throw InsufficientStockException(short);
      }
      final production = await _db
          .into(_db.productions)
          .insertReturning(
            ProductionsCompanion.insert(
              businessId: product.businessId,
              productId: productId,
              orderId: Value(orderId),
              batchQty: dbl(batchQty),
              outputQty: dbl(output),
              materialCost: 0,
              otherCost: 0,
              hppPerPcs: 0,
              producedAt: when,
              note: Value(note),
            ),
          );
      final material = await _stock.recordProductionUsage(
        productionId: production.id,
        usage: usage,
        at: when,
      );
      final other = toRupiah(
        costing.hpp.otherCostPerBatch * batchQty +
            costing.hpp.otherCostPerPcs * output,
      );
      final hppPerPcs = divide(rupiah(material + other), output);
      await (_db.update(
        _db.productions,
      )..where((t) => t.id.equals(production.id))).write(
        ProductionsCompanion(
          materialCost: Value(material),
          otherCost: Value(other),
          hppPerPcs: Value(dbl(hppPerPcs)),
        ),
      );
      final mode = product.stockDeductMode ?? business.stockDeductMode;
      if (mode == StockDeductMode.onProduction) {
        await _insertProductMovement(
          productId,
          type: ProductMovementType.production,
          qty: output,
          unitCost: hppPerPcs,
          refType: 'production',
          refId: production.id,
          at: when,
        );
        await _recomputeProductStock(productId);
      }
      return production.id;
    });
  }

  /// Membatalkan produksi: bahan dan stok produk jadi dikembalikan (FR-9.1).
  Future<void> voidProduction(String productionId, {required String reason}) {
    return _db.transaction(() async {
      final production = await (_db.select(
        _db.productions,
      )..where((t) => t.id.equals(productionId))).getSingle();
      if (production.voidedAt != null) {
        throw StateError('Produksi ini sudah dibatalkan.');
      }
      await (_db.update(
        _db.productions,
      )..where((t) => t.id.equals(productionId))).write(
        ProductionsCompanion(
          voidedAt: Value(_now()),
          voidReason: Value(reason),
          updatedAt: Value(_now()),
        ),
      );
      await _stock.reverseByRef('production', productionId, reason);
      final movements =
          await (_db.select(_db.productStockMovements)..where(
                (t) =>
                    t.refType.equals('production') &
                    t.refId.equals(productionId) &
                    t.reversalOfId.isNull(),
              ))
              .get();
      for (final m in movements) {
        await _insertProductMovement(
          m.productId,
          type: m.type,
          qty: -dec(m.qty),
          unitCost: dec(m.unitCost),
          refType: m.refType,
          refId: m.refId,
          reversalOfId: m.id,
          at: m.occurredAt,
          note: reason,
        );
      }
      await _recomputeProductStock(production.productId);
    });
  }

  /// Stok awal produk jadi (mis. sisa jualan sebelum memakai aplikasi),
  /// dinilai dengan HPP terkini (FR-4.5).
  Future<void> recordProductOpening(String productId, Decimal qty) {
    if (qty <= Decimal.zero) {
      throw ArgumentError.value(qty, 'qty', 'harus > 0');
    }
    return _db.transaction(() async {
      final product = await _product(productId);
      final costing = await loadProductCosting(_db, product);
      await _insertProductMovement(
        productId,
        type: ProductMovementType.opening,
        qty: qty,
        unitCost: costing.hpp.hppPerPcs,
        at: _now(),
      );
      await _recomputeProductStock(productId);
    });
  }

  Stream<List<Production>> watchProductions(String productId) =>
      (_db.select(_db.productions)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([(t) => OrderingTerm.desc(t.producedAt)]))
          .watch();

  // ---------------------------------------------------------- Internal

  void _validate(ProductInput input) {
    if (input.name.trim().isEmpty) {
      throw ArgumentError('Nama menu belum diisi.');
    }
    if (input.yieldQty <= Decimal.zero) {
      throw ArgumentError.value(input.yieldQty, 'yieldQty', 'harus > 0');
    }
    if (input.sellingPrice < 0) {
      throw ArgumentError.value(input.sellingPrice, 'sellingPrice', '≥ 0');
    }
  }

  Future<void> _writeChildren(String productId, ProductInput input) async {
    final seen = <String>{};
    for (final r in input.recipe) {
      if (r.qtyBase <= Decimal.zero || !seen.add(r.ingredientId)) continue;
      await _db
          .into(_db.recipeItems)
          .insert(
            RecipeItemsCompanion.insert(
              productId: productId,
              ingredientId: r.ingredientId,
              qtyBase: dbl(r.qtyBase),
            ),
          );
    }
    for (final c in input.costs) {
      await _db
          .into(_db.productCosts)
          .insert(
            ProductCostsCompanion.insert(
              productId: productId,
              name: c.name.trim(),
              costType: c.costType,
              amount: c.amount,
              basis: c.basis,
              laborHours: Value(
                c.laborHours == null ? null : dbl(c.laborHours!),
              ),
            ),
          );
    }
  }

  Future<void> _insertProductMovement(
    String productId, {
    required ProductMovementType type,
    required Decimal qty,
    required Decimal unitCost,
    required DateTime at,
    String? refType,
    String? refId,
    String? reversalOfId,
    String? note,
  }) => _db
      .into(_db.productStockMovements)
      .insert(
        ProductStockMovementsCompanion.insert(
          productId: productId,
          type: type,
          qty: dbl(qty),
          unitCost: dbl(unitCost),
          value: toRupiah(qty * unitCost),
          balanceAfter: 0,
          avgCostAfter: 0,
          refType: Value(refType),
          refId: Value(refId),
          reversalOfId: Value(reversalOfId),
          occurredAt: at,
          note: Value(note),
        ),
      );

  Future<void> _recomputeProductStock(String productId) async {
    final rows = await (_db.select(
      _db.productStockMovements,
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
      final res = result.rows[i];
      await (_db.update(
        _db.productStockMovements,
      )..where((t) => t.id.equals(rows[i].id))).write(
        ProductStockMovementsCompanion(
          unitCost: res.cancelled
              ? const Value.absent()
              : Value(dbl(res.unitCost)),
          value: res.cancelled ? const Value.absent() : Value(res.value),
          balanceAfter: Value(dbl(res.balanceAfter)),
          avgCostAfter: Value(dbl(res.avgCostAfter)),
        ),
      );
    }
    await (_db.update(
      _db.products,
    )..where((t) => t.id.equals(productId))).write(
      ProductsCompanion(
        currentStock: Value(dbl(result.stock)),
        stockUnitCost: Value(dbl(result.avgUnitCost)),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<Product> _product(String id) =>
      (_db.select(_db.products)..where((t) => t.id.equals(id))).getSingle();

  Future<Business> _business(String id) =>
      (_db.select(_db.businesses)..where((t) => t.id.equals(id))).getSingle();

  /// Muat ulang setiap kali tabel yang memengaruhi HPP atau stok berubah.
  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.products,
        _db.recipeItems,
        _db.productCosts,
        _db.ingredients,
        _db.businesses,
      ]),
    )) {
      yield await load();
    }
  }
}
