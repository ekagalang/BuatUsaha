import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'cost_cascade.dart';
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
    this.safetyStock,
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

  /// Stok jaga menu ready stock (FR-12.10); kosong = 0.
  final Decimal? safetyStock;
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
              safetyStock: Value(dbl(input.safetyStock ?? Decimal.zero)),
              stockDeductMode: Value(input.stockDeductMode),
              targetMarkupPct: Value(
                input.targetMarkupPct == null
                    ? null
                    : dbl(input.targetMarkupPct!),
              ),
            ),
          );
      await _writeChildren(product.id, input);
      await refreshProductHpp(_db, product.id, cause: HppChangeCause.created);
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
          safetyStock: Value(dbl(input.safetyStock ?? Decimal.zero)),
          stockDeductMode: Value(input.stockDeductMode),
          targetMarkupPct: Value(
            input.targetMarkupPct == null ? null : dbl(input.targetMarkupPct!),
          ),
          updatedAt: Value(_now()),
        ),
      );
      await _replaceChildren(id, input);
      await refreshProductHpp(_db, id, cause: HppChangeCause.recipe);
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
      safetyStock: dec(product.safetyStock),
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
      if (orderId != null) {
        // Produksi untuk pesanan → pesanan Diproses (FR-4.3).
        await (_db.update(_db.orders)..where(
              (t) =>
                  t.id.equals(orderId) &
                  t.status.equalsValue(OrderStatus.newOrder),
            ))
            .write(
              OrdersCompanion(
                status: const Value(OrderStatus.inProgress),
                updatedAt: Value(_now()),
              ),
            );
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
      await reverseProductByRef('production', productionId, reason);
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

  /// Produk jadi keluar (terjual, dibuang, penyesuaian) dengan HPP rata-rata
  /// stok saat itu. [qty] positif = jumlah keluar; penyesuaian boleh negatif
  /// (= masuk). Mengembalikan HPP per pcs yang dipakai. Boleh dipanggil di
  /// dalam transaksi pemanggil.
  Future<Decimal> issueProduct(
    String productId, {
    required ProductMovementType type,
    required Decimal qty,
    DateTime? at,
    WasteReason? reason,
    String? refType,
    String? refId,
    String? note,
  }) {
    if (qty == Decimal.zero) {
      throw ArgumentError.value(qty, 'qty', 'tidak boleh 0');
    }
    return _db.transaction(() async {
      final id = await _insertProductMovement(
        productId,
        type: type,
        qty: -qty,
        unitCost: Decimal.zero,
        at: (at ?? _now()).toUtc(),
        reason: reason,
        refType: refType,
        refId: refId,
        note: note,
      );
      await _recomputeProductStock(productId);
      final row = await (_db.select(
        _db.productStockMovements,
      )..where((t) => t.id.equals(id))).getSingle();
      return dec(row.unitCost);
    });
  }

  /// Produk jadi masuk di luar produksi dengan HPP tertentu, mis. barang
  /// pesanan pre-order yang batal sebelum dicatat dibuang.
  Future<void> receiveProduct(
    String productId, {
    required Decimal qty,
    required Decimal unitCost,
    required DateTime at,
    String? refType,
    String? refId,
    String? note,
  }) => _db.transaction(() async {
    await _insertProductMovement(
      productId,
      type: ProductMovementType.opening,
      qty: qty,
      unitCost: unitCost,
      at: at.toUtc(),
      refType: refType,
      refId: refId,
      note: note,
    );
    await _recomputeProductStock(productId);
  });

  Future<ProductCosting> costingOf(String productId) async =>
      loadProductCosting(_db, await _product(productId));

  /// Membalik semua mutasi produk jadi dari satu sumber (produksi, pesanan,
  /// Tutup hari) lalu menghitung ulang stok produk terkait.
  Future<void> reverseProductByRef(
    String refType,
    String refId,
    String reason,
  ) async {
    final rows = await (_db.select(
      _db.productStockMovements,
    )..where((t) => t.refType.equals(refType) & t.refId.equals(refId))).get();
    final reversed = {
      for (final r in rows)
        if (r.reversalOfId != null) r.reversalOfId!,
    };
    final productIds = <String>{};
    for (final m in rows) {
      if (m.reversalOfId != null || reversed.contains(m.id)) continue;
      await _insertProductMovement(
        m.productId,
        type: m.type,
        qty: -dec(m.qty),
        unitCost: dec(m.unitCost),
        reason: m.reason,
        refType: m.refType,
        refId: m.refId,
        reversalOfId: m.id,
        at: m.occurredAt,
        note: reason,
      );
      productIds.add(m.productId);
    }
    for (final id in productIds) {
      await _recomputeProductStock(id);
    }
  }

  /// Kartu stok produk jadi, terbaru di atas.
  Stream<List<ProductStockMovement>> watchProductCard(String productId) =>
      (_db.select(_db.productStockMovements)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.occurredAt),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

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

  /// Resep dan biaya lain diperbarui di tempat: baris yang masih ada tetap
  /// memakai id-nya, supaya menu yang diubah di dua HP tidak dobel setelah
  /// sinkron (FR-10.4).
  Future<void> _replaceChildren(String productId, ProductInput input) async {
    final oldLines = {
      for (final r in await (_db.select(
        _db.recipeItems,
      )..where((t) => t.productId.equals(productId))).get())
        r.ingredientId: r,
    };
    final seen = <String>{};
    for (final r in input.recipe) {
      if (r.qtyBase <= Decimal.zero || !seen.add(r.ingredientId)) continue;
      final old = oldLines.remove(r.ingredientId);
      if (old == null) {
        await _db
            .into(_db.recipeItems)
            .insert(
              RecipeItemsCompanion.insert(
                productId: productId,
                ingredientId: r.ingredientId,
                qtyBase: dbl(r.qtyBase),
              ),
            );
      } else if (old.qtyBase != dbl(r.qtyBase)) {
        await (_db.update(
          _db.recipeItems,
        )..where((t) => t.id.equals(old.id))).write(
          RecipeItemsCompanion(
            qtyBase: Value(dbl(r.qtyBase)),
            updatedAt: Value(_now()),
          ),
        );
      }
    }
    for (final old in oldLines.values) {
      await (_db.delete(
        _db.recipeItems,
      )..where((t) => t.id.equals(old.id))).go();
    }

    final oldCosts =
        await (_db.select(_db.productCosts)
              ..where((t) => t.productId.equals(productId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    for (final c in input.costs) {
      final name = c.name.trim();
      final hours = c.laborHours == null ? null : dbl(c.laborHours!);
      final i = oldCosts.indexWhere(
        (o) => o.name == name && o.costType == c.costType,
      );
      if (i < 0) {
        await _insertCost(productId, c);
        continue;
      }
      final old = oldCosts.removeAt(i);
      // Nominal upah pemilik dihitung refreshProductHpp dari jam × upah.
      final amount = hours == null ? c.amount : old.amount;
      if (old.amount != amount ||
          old.basis != c.basis ||
          old.laborHours != hours) {
        await (_db.update(
          _db.productCosts,
        )..where((t) => t.id.equals(old.id))).write(
          ProductCostsCompanion(
            amount: Value(amount),
            basis: Value(c.basis),
            laborHours: Value(hours),
            updatedAt: Value(_now()),
          ),
        );
      }
    }
    for (final old in oldCosts) {
      await (_db.delete(
        _db.productCosts,
      )..where((t) => t.id.equals(old.id))).go();
    }
  }

  Future<void> _insertCost(String productId, CostInput c) => _db
      .into(_db.productCosts)
      .insert(
        ProductCostsCompanion.insert(
          productId: productId,
          name: c.name.trim(),
          costType: c.costType,
          amount: c.amount,
          basis: c.basis,
          laborHours: Value(c.laborHours == null ? null : dbl(c.laborHours!)),
        ),
      );

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
      await _insertCost(productId, c);
    }
  }

  Future<String> _insertProductMovement(
    String productId, {
    required ProductMovementType type,
    required Decimal qty,
    required Decimal unitCost,
    required DateTime at,
    WasteReason? reason,
    String? refType,
    String? refId,
    String? reversalOfId,
    String? note,
  }) async =>
      (await _db
              .into(_db.productStockMovements)
              .insertReturning(
                ProductStockMovementsCompanion.insert(
                  productId: productId,
                  type: type,
                  qty: dbl(qty),
                  unitCost: dbl(unitCost),
                  value: toRupiah(qty * unitCost),
                  balanceAfter: 0,
                  avgCostAfter: 0,
                  reason: Value(reason),
                  refType: Value(refType),
                  refId: Value(refId),
                  reversalOfId: Value(reversalOfId),
                  occurredAt: at,
                  note: Value(note),
                ),
              ))
          .id;

  Future<void> _recomputeProductStock(String productId) =>
      recomputeProductStock(_db, productId);

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
