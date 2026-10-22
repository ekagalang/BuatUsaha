import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../../domain/stock/ingredient_ledger.dart';
import '../../domain/stock/units.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'cost_cascade.dart';
import 'hpp_refresher.dart';

const _purchaseItemRef = 'purchase_item';

DateTime _now() => DateTime.now().toUtc();

extension IngredientUnitLabel on Ingredient {
  /// Nama satuan dasar yang tampil: g, ml, atau nama satuan jumlah bahan ini
  /// (butir, lembar, …; bawaan pcs) (FR-20.3).
  String get unitLabel {
    final count = countUnit?.trim();
    return baseUnit == BaseUnit.pcs && count != null && count.isNotEmpty
        ? count
        : baseUnit.code;
  }
}

/// Satu baris belanja dalam satuan beli (FR-1.3).
class PurchaseLineInput {
  const PurchaseLineInput({
    required this.ingredientId,
    required this.qty,
    required this.unitName,
    required this.factorToBase,
    required this.totalPrice,
  });

  final String ingredientId;
  final Decimal qty;
  final String unitName;
  final Decimal factorToBase;
  final int totalPrice;

  Decimal get qtyBase => toBaseQty(qty, factorToBase);
}

class PurchaseInput {
  const PurchaseInput({
    required this.purchasedAt,
    required this.lines,
    this.supplierId,
    this.note,
    this.cashAccountId,
  });

  final DateTime purchasedAt;
  final List<PurchaseLineInput> lines;
  final String? supplierId;
  final String? note;

  /// Dibayar dari akun kas ini (FR-15.2); `null` = Tunai.
  final String? cashAccountId;
}

/// Bahan beserta angka turunan untuk daftar Bahan.
class IngredientView {
  const IngredientView(this.ingredient);

  final Ingredient ingredient;

  Decimal get stock => dec(ingredient.currentStock);
  Decimal get minStock => dec(ingredient.minStock);

  /// `null` = belum punya harga.
  Decimal? get avgUnitCost {
    final avg = ingredient.avgUnitCost;
    return avg == null ? null : dec(avg);
  }

  bool get isLow => isLowStock(stock: stock, minStock: minStock);

  /// Diarsipkan: tidak tampil di daftar dan pilihan, tetap dihitung di nilai
  /// modal (FR-20.2).
  bool get isArchived => ingredient.archivedAt != null;

  /// Nilai modal sisa bahan ini (stok × harga rata-rata).
  int get value => totalStockValue([
    StockValueLine(
      ingredientId: ingredient.id,
      qty: stock,
      avgUnitCost: avgUnitCost,
    ),
  ]);
}

/// Satu baris kartu stok (FR-1.5).
class StockCardEntry {
  const StockCardEntry({
    required this.movement,
    required this.cancelled,
    required this.isReversal,
  });

  final StockMovement movement;

  /// Baris asli yang sudah dibatalkan.
  final bool cancelled;

  /// Mutasi pembalik dari sebuah pembatalan.
  final bool isReversal;
}

/// Bahan, belanja, stok awal, penyesuaian, opname, dan koreksinya.
///
/// Stok dan harga rata-rata di tabel `ingredients` adalah cache: setiap
/// perubahan menghitung ulang buku mutasi bahan yang terkena (FR-9.3), dalam
/// transaksi yang sama.
class StockRepository {
  StockRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------- Bahan

  /// Bahan baru, opsional dengan stok awal (harus berharga) atau harga
  /// perkiraan (FR-1.1, FR-1.7).
  Future<Ingredient> createIngredient({
    required String businessId,
    required String name,
    required BaseUnit baseUnit,
    IngredientCategory category = IngredientCategory.raw,
    Decimal? minStock,
    String? note,
    Decimal? openingQty,
    Decimal? openingUnitCost,
    Decimal? estimatedUnitCost,
    DateTime? at,
  }) {
    return _db.transaction(() async {
      final ingredient = await _db
          .into(_db.ingredients)
          .insertReturning(
            IngredientsCompanion.insert(
              businessId: businessId,
              name: name.trim(),
              baseUnit: baseUnit,
              category: Value(category),
              minStock: Value(dbl(minStock ?? Decimal.zero)),
              note: Value(note),
            ),
          );
      final when = (at ?? _now()).toUtc();
      if (openingQty != null && openingQty > Decimal.zero) {
        if (openingUnitCost == null) {
          throw ArgumentError('Stok awal harus disertai harganya.');
        }
        await _insertOpening(ingredient.id, openingQty, openingUnitCost, when);
      } else if (estimatedUnitCost != null) {
        await _insertEstimate(ingredient.id, estimatedUnitCost, when);
      }
      return _recompute(ingredient.id);
    });
  }

  Future<Ingredient> updateIngredient(
    String id, {
    String? name,
    IngredientCategory? category,
    Decimal? minStock,
    String? note,
    String? countUnit,
  }) {
    return _db.transaction(() async {
      final unit = countUnit?.trim();
      await (_db.update(_db.ingredients)..where((t) => t.id.equals(id))).write(
        IngredientsCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          category: category == null ? const Value.absent() : Value(category),
          minStock: minStock == null
              ? const Value.absent()
              : Value(dbl(minStock)),
          note: note == null ? const Value.absent() : Value(note),
          countUnit: unit == null
              ? const Value.absent()
              : Value(
                  unit.isEmpty || unit.toLowerCase() == 'pcs' ? null : unit,
                ),
          updatedAt: Value(_now()),
        ),
      );
      return _recompute(id);
    });
  }

  /// Belum ada stok, transaksi, atau resep yang memakai bahan ini: cara
  /// hitungnya bisa diganti tanpa konversi.
  Future<bool> needsConversion(String ingredientId) async {
    final ingredient = await _ingredient(ingredientId);
    if (ingredient.currentStock != 0) return true;
    final moved =
        await (_db.select(_db.stockMovements)
              ..where(
                (t) =>
                    t.ingredientId.equals(ingredientId) &
                    t.qtyBase.equals(0).not(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (moved != null) return true;
    final inRecipe =
        await (_db.select(_db.recipeItems)
              ..where((t) => t.ingredientId.equals(ingredientId))
              ..limit(1))
            .getSingleOrNull();
    return inRecipe != null;
  }

  /// Ganti cara hitung bahan (FR-20.2). [factor] = jumlah satuan baru per 1
  /// satuan lama (1 butir = 60 g → 60). Stok, mutasi, belanja, satuan beli,
  /// takaran resep, dan daftar belanja dikonversi, lalu harga rata-rata dan
  /// HPP dihitung ulang.
  Future<Ingredient> changeBaseUnit(
    String ingredientId,
    BaseUnit unit, {
    Decimal? factor,
  }) {
    final f = dbl(factor ?? Decimal.one);
    if (f <= 0) throw ArgumentError.value(factor, 'factor', 'harus > 0');
    return _db.transaction(() async {
      final args = [f, f, f, f, ingredientId];
      await _db.customStatement(
        'UPDATE stock_movements SET qty_base = qty_base * ?, '
        'unit_cost = unit_cost / ?, balance_after = balance_after * ?, '
        'avg_cost_after = avg_cost_after / ? WHERE ingredient_id = ?',
        args,
      );
      await _db.customStatement(
        'UPDATE purchase_items SET qty_base = qty_base * ?, '
        'factor_to_base = factor_to_base * ?, '
        'unit_cost_base = unit_cost_base / ? WHERE ingredient_id = ?',
        [f, f, f, ingredientId],
      );
      await _db.customStatement(
        'UPDATE ingredient_units SET factor_to_base = factor_to_base * ? '
        'WHERE ingredient_id = ?',
        [f, ingredientId],
      );
      await _db.customStatement(
        'UPDATE recipe_items SET qty_base = qty_base * ? '
        'WHERE ingredient_id = ?',
        [f, ingredientId],
      );
      await _db.customStatement(
        'UPDATE recipe_items SET unit_factor = unit_factor * ? '
        'WHERE ingredient_id = ? AND unit_factor IS NOT NULL',
        [f, ingredientId],
      );
      await _db.customStatement(
        'UPDATE shopping_list_items SET factor_to_base = factor_to_base * ? '
        'WHERE ingredient_id = ?',
        [f, ingredientId],
      );
      final ingredient = await _ingredient(ingredientId);
      await (_db.update(
        _db.ingredients,
      )..where((t) => t.id.equals(ingredientId))).write(
        IngredientsCompanion(
          baseUnit: Value(unit),
          minStock: Value(ingredient.minStock * f),
          countUnit: unit == BaseUnit.pcs
              ? const Value.absent()
              : const Value(null),
          updatedAt: Value(_now()),
        ),
      );
      _db.markTablesUpdated([
        _db.stockMovements,
        _db.purchaseItems,
        _db.ingredientUnits,
        _db.recipeItems,
        _db.shoppingListItems,
      ]);
      final result = await _recompute(ingredientId);
      final products = await (_db.select(
        _db.recipeItems,
      )..where((t) => t.ingredientId.equals(ingredientId))).get();
      for (final p in {for (final r in products) r.productId}) {
        await refreshProductHpp(_db, p, cause: HppChangeCause.recipe);
      }
      return result;
    });
  }

  /// Stok awal untuk bahan yang belum pernah dibelanjakan (FR-1.7).
  Future<Ingredient> recordOpening(
    String ingredientId, {
    required Decimal qtyBase,
    required Decimal unitCost,
    DateTime? at,
  }) {
    if (qtyBase <= Decimal.zero) {
      throw ArgumentError.value(qtyBase, 'qtyBase', 'harus > 0');
    }
    return _db.transaction(() async {
      await _ensureNoPurchaseYet(ingredientId);
      await _insertOpening(
        ingredientId,
        qtyBase,
        unitCost,
        (at ?? _now()).toUtc(),
      );
      return _recompute(ingredientId);
    });
  }

  /// Harga perkiraan per satuan dasar untuk bahan yang belum punya harga
  /// dari belanja; diganti otomatis oleh belanja pertama (FR-1.7).
  Future<Ingredient> setPriceEstimate(
    String ingredientId,
    Decimal unitCost, {
    DateTime? at,
  }) {
    return _db.transaction(() async {
      await _ensureNoPurchaseYet(ingredientId);
      await _insertEstimate(ingredientId, unitCost, (at ?? _now()).toUtc());
      return _recompute(ingredientId);
    });
  }

  /// Bahan yang belum punya transaksi selain stok awal atau harga perkiraan;
  /// stoknya boleh diisi sebagai stok awal (FR-20.6).
  Future<bool> canSetInitialStock(String ingredientId) async =>
      (await _ledgerRows(ingredientId))
          .every((r) => r.type == MovementType.opening);

  /// Isi atau ganti stok awal bahan yang belum punya transaksi: masuk nilai
  /// modal, tidak dihitung laba (FR-20.6). [qtyBase] 0 = hanya harga.
  Future<Ingredient> setInitialStock(
    String ingredientId, {
    required Decimal qtyBase,
    required Decimal unitCost,
    DateTime? at,
  }) {
    if (qtyBase < Decimal.zero) {
      throw ArgumentError.value(qtyBase, 'qtyBase', 'harus ≥ 0');
    }
    if (unitCost <= Decimal.zero) {
      throw ArgumentError.value(unitCost, 'unitCost', 'harus > 0');
    }
    return _db.transaction(() async {
      final rows = await _ledgerRows(ingredientId);
      if (rows.any((r) => r.type != MovementType.opening)) {
        throw StateError(
          'Bahan ini sudah punya transaksi; pakai Penyesuaian atau Stock '
          'opname.',
        );
      }
      final when = (at ?? rows.firstOrNull?.occurredAt ?? _now()).toUtc();
      for (final r in rows) {
        await (_db.delete(
          _db.stockMovements,
        )..where((t) => t.id.equals(r.id))).go();
      }
      if (qtyBase > Decimal.zero) {
        await _insertOpening(ingredientId, qtyBase, unitCost, when);
      } else {
        await _insertEstimate(ingredientId, unitCost, when);
      }
      return _recompute(ingredientId);
    });
  }

  /// Perbaikan sekali setelah update ke skema v7 (FR-20.6): bahan yang
  /// riwayatnya hanya harga perkiraan lalu opname/penyesuaian (stok pertama
  /// diisi lewat opname) diberi satu stok awal, dan opname/penyesuaiannya
  /// dibatalkan, sehingga stok itu tidak lagi terhitung laba. Id baris baru
  /// tetap (dari id baris asal) supaya dua HP yang sama-sama memperbaiki
  /// tidak membuat baris ganda. Mengembalikan jumlah bahan yang diperbaiki.
  Future<int> runOpeningFix(String businessId) async {
    final flag =
        await (_db.select(_db.syncState)
              ..where((t) => t.entity.equals(AppDatabase.openingFixKey)))
            .getSingleOrNull();
    if (flag == null) return 0;
    final before = flag.lastPulledAt ?? _now();
    var fixed = 0;
    await _db.transaction(() async {
      final ingredients = await (_db.select(
        _db.ingredients,
      )..where((t) => t.businessId.equals(businessId))).get();
      for (final i in ingredients) {
        if (await _fixOpening(i, before)) fixed++;
      }
      await (_db.delete(
        _db.syncState,
      )..where((t) => t.entity.equals(AppDatabase.openingFixKey))).go();
    });
    return fixed;
  }

  Future<bool> _fixOpening(Ingredient ingredient, DateTime before) async {
    final rows = await _ledgerRows(ingredient.id);
    final counts = <StockMovement>[];
    for (final r in rows) {
      if (!r.createdAt.isBefore(before) || r.reversalOfId != null) {
        return false;
      }
      switch (r.type) {
        case MovementType.opening:
          if (r.qtyBase != 0) return false;
        case MovementType.opname || MovementType.adjustment:
          counts.add(r);
        default:
          return false;
      }
    }
    if (counts.isEmpty) return false;
    final stock = dec(ingredient.currentStock);
    final avg = ingredient.avgUnitCost;
    if (stock < Decimal.zero || (stock > Decimal.zero && avg == null)) {
      return false;
    }
    if (stock > Decimal.zero) {
      final unitCost = dec(avg!);
      await _db
          .into(_db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: Value('${counts.first.id}-awal'),
              ingredientId: ingredient.id,
              type: MovementType.opening,
              qtyBase: dbl(stock),
              unitCost: dbl(unitCost),
              value: toRupiah(stock * unitCost),
              balanceAfter: 0,
              avgCostAfter: 0,
              occurredAt: counts.first.occurredAt,
              note: const Value('Stok awal (dari stock opname)'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    for (final r in counts) {
      await _db
          .into(_db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              id: Value('${r.id}-batal'),
              ingredientId: r.ingredientId,
              type: r.type,
              qtyBase: -r.qtyBase,
              unitCost: r.unitCost,
              value: -r.value,
              balanceAfter: 0,
              avgCostAfter: 0,
              reversalOfId: Value(r.id),
              occurredAt: r.occurredAt,
              note: const Value('Dijadikan stok awal'),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await _recompute(ingredient.id);
    return true;
  }

  Future<void> addCustomUnit(
    String ingredientId, {
    required String unitName,
    required Decimal factorToBase,
    bool forRecipe = false,
  }) {
    if (factorToBase <= Decimal.zero) {
      throw ArgumentError.value(factorToBase, 'factorToBase', 'harus > 0');
    }
    final name = unitName.trim();
    if (name.isEmpty) throw ArgumentError('Nama satuan belum diisi.');
    return _db.transaction(() async {
      // Nama yang sama di bahan ini (tanpa beda huruf/spasi) = satuan yang
      // sama: isinya diperbarui (FR-20.3).
      final same = [
        for (final u in await _units(ingredientId))
          if (normalizeUnitName(u.unitName) == normalizeUnitName(name)) u,
      ];
      if (same.isEmpty) {
        await _db
            .into(_db.ingredientUnits)
            .insert(
              IngredientUnitsCompanion.insert(
                ingredientId: ingredientId,
                unitName: name,
                factorToBase: dbl(factorToBase),
                forRecipe: Value(forRecipe),
              ),
            );
        return;
      }
      await (_db.update(
        _db.ingredientUnits,
      )..where((t) => t.id.equals(same.first.id))).write(
        IngredientUnitsCompanion(
          factorToBase: Value(dbl(factorToBase)),
          hidden: const Value(false),
          forRecipe: Value(same.first.forRecipe && forRecipe),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  /// Sembunyikan atau tampilkan satuan bawaan (kg, lusin, …) atau satuan
  /// buatan sendiri di bahan ini (FR-20.3).
  Future<void> setUnitHidden(
    String ingredientId,
    String unitName, {
    required bool hidden,
  }) async {
    final ingredient = await _ingredient(ingredientId);
    final rows = await _units(ingredientId);
    final row = rows
        .where(
          (u) => normalizeUnitName(u.unitName) == normalizeUnitName(unitName),
        )
        .firstOrNull;
    if (row != null) {
      await (_db.update(
        _db.ingredientUnits,
      )..where((t) => t.id.equals(row.id))).write(
        IngredientUnitsCompanion(
          hidden: Value(hidden),
          updatedAt: Value(_now()),
        ),
      );
      return;
    }
    if (!hidden) return;
    final builtIn = builtInUnits(ingredient.baseUnit)
        .where((u) => u.$1 == normalizeUnitName(unitName))
        .firstOrNull;
    if (builtIn == null) return;
    await _db
        .into(_db.ingredientUnits)
        .insert(
          IngredientUnitsCompanion.insert(
            ingredientId: ingredientId,
            unitName: builtIn.$1,
            factorToBase: builtIn.$2.toDouble(),
            hidden: const Value(true),
          ),
        );
  }

  Future<List<IngredientUnit>> _units(String ingredientId) =>
      (_db.select(_db.ingredientUnits)
            ..where((t) => t.ingredientId.equals(ingredientId))
            ..orderBy([(t) => OrderingTerm.asc(t.unitName)]))
          .get();

  Stream<List<IngredientUnit>> watchUnits(String ingredientId) =>
      (_db.select(_db.ingredientUnits)
            ..where((t) => t.ingredientId.equals(ingredientId))
            ..orderBy([(t) => OrderingTerm.asc(t.unitName)]))
          .watch();

  /// Satuan beli bawaan + konversi khusus bahan ini (FR-1.2). Dengan
  /// [forRecipe], satuan resep dan satuan dapur baku ikut (FR-20.3). Satuan
  /// yang disembunyikan tidak ikut.
  Future<List<UnitOption>> unitOptions(
    String ingredientId, {
    bool forRecipe = false,
  }) async {
    final ingredient = await _ingredient(ingredientId);
    final rows = await _units(ingredientId);
    final hidden = {
      for (final u in rows)
        if (u.hidden) normalizeUnitName(u.unitName),
    };
    return [
      for (final o in unitOptionsFor(
        ingredient.baseUnit,
        [
          for (final u in rows)
            if (!u.hidden && (forRecipe || !u.forRecipe))
              UnitOption(
                name: u.unitName,
                factorToBase: dec(u.factorToBase),
                isCustom: true,
                forRecipe: u.forRecipe,
              ),
        ],
        ingredient.unitLabel,
        forRecipe,
      ))
        if (!hidden.contains(normalizeUnitName(o.name))) o,
    ];
  }

  /// Nama satuan yang pernah dipakai di usaha ini, untuk saran saat membuat
  /// satuan baru (FR-20.3).
  Future<List<String>> unitLibrary(String businessId) async {
    final rows =
        await (_db.select(_db.ingredientUnits).join([
              innerJoin(
                _db.ingredients,
                _db.ingredients.id.equalsExp(_db.ingredientUnits.ingredientId),
              ),
            ])..where(
              _db.ingredients.businessId.equals(businessId) &
                  _db.ingredientUnits.hidden.equals(false),
            ))
            .get();
    final names = <String, String>{};
    for (final r in rows) {
      final name = r.readTable(_db.ingredientUnits).unitName;
      names.putIfAbsent(normalizeUnitName(name), () => name);
    }
    return names.values.toList()..sort();
  }

  Stream<List<IngredientView>> watchIngredients(String businessId) {
    final query = _db.select(_db.ingredients)
      ..where((t) => t.businessId.equals(businessId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch().map(
      (rows) => [for (final r in rows) IngredientView(r)],
    );
  }

  Stream<IngredientView> watchIngredient(String id) => (_db.select(
    _db.ingredients,
  )..where((t) => t.id.equals(id))).watchSingle().map(IngredientView.new);

  // -------------------------------------------------------------- Belanja

  Future<String> recordPurchase(String businessId, PurchaseInput input) {
    return _db.transaction(() async {
      final (id, ingredientIds) = await _insertPurchase(businessId, input);
      await _recomputeAll(ingredientIds);
      return id;
    });
  }

  /// Membatalkan belanja: belanja ditandai Dibatalkan dan tiap mutasinya
  /// dibalik pada tanggal yang sama (FR-9.1).
  Future<void> voidPurchase(String purchaseId, {required String reason}) {
    return _db.transaction(() async {
      final (_, ingredientIds) = await _voidPurchase(purchaseId, reason);
      await _recomputeAll(ingredientIds);
    });
  }

  /// Belanja asal sebuah mutasi belanja (`refId` = id item belanja).
  Future<String> purchaseIdOfItem(String purchaseItemId) async {
    final item = await (_db.select(
      _db.purchaseItems,
    )..where((t) => t.id.equals(purchaseItemId))).getSingle();
    return item.purchaseId;
  }

  /// Edit belanja = batalkan yang lama + catat yang baru (FR-9.2).
  Future<String> replacePurchase(
    String purchaseId,
    PurchaseInput input, {
    String reason = 'Diedit',
  }) {
    return _db.transaction(() async {
      final (businessId, voided) = await _voidPurchase(purchaseId, reason);
      final (newId, added) = await _insertPurchase(businessId, input);
      await _recomputeAll({...voided, ...added});
      return newId;
    });
  }

  // --------------------------------------------- Penyesuaian dan opname

  /// Penyesuaian manual: positif = tambah, negatif = kurangi (FR-1.4).
  Future<Ingredient> recordAdjustment(
    String ingredientId, {
    required Decimal qtyBase,
    String? note,
    DateTime? at,
  }) => _recordIssueOrAdjustment(
    ingredientId,
    MovementType.adjustment,
    qtyBase,
    note,
    at,
  );

  /// Bahan rusak atau kedaluwarsa; dicatat sebagai kerugian (FR-1.4).
  Future<Ingredient> recordWaste(
    String ingredientId, {
    required Decimal qtyBase,
    String? note,
    DateTime? at,
  }) {
    if (qtyBase <= Decimal.zero) {
      throw ArgumentError.value(qtyBase, 'qtyBase', 'harus > 0');
    }
    return _recordIssueOrAdjustment(
      ingredientId,
      MovementType.waste,
      -qtyBase,
      note,
      at,
    );
  }

  /// Stock opname: stok fisik [countedQty] pada [at]; selisih terhadap saldo
  /// buku pada saat itu dicatat sebagai mutasi `OPNAME` (FR-1.4). Mengembalikan
  /// selisihnya.
  Future<Decimal> recordOpname(
    String ingredientId, {
    required Decimal countedQty,
    String? note,
    DateTime? at,
  }) {
    if (countedQty < Decimal.zero) {
      throw ArgumentError.value(countedQty, 'countedQty', 'harus ≥ 0');
    }
    final when = (at ?? _now()).toUtc();
    return _db.transaction(() async {
      final rows = await _ledgerRows(ingredientId);
      final upTo = [
        for (final r in rows)
          if (!r.occurredAt.isAfter(when)) r,
      ];
      final bookStock = replayIngredientLedger([
        for (final r in upTo) _toLedger(r),
      ]).stock;
      final delta = countedQty - bookStock;
      await _insertMovement(
        ingredientId,
        type: MovementType.opname,
        qtyBase: delta,
        occurredAt: when,
        note: note,
      );
      await _recompute(ingredientId);
      return delta;
    });
  }

  /// Membatalkan stok awal, harga perkiraan, penyesuaian, bahan rusak, atau
  /// opname. Mutasi belanja dibatalkan lewat [voidPurchase].
  Future<Ingredient> voidMovement(String movementId, {required String reason}) {
    return _db.transaction(() async {
      final movement = await (_db.select(
        _db.stockMovements,
      )..where((t) => t.id.equals(movementId))).getSingle();
      if (movement.refType == _purchaseItemRef) {
        throw StateError('Mutasi belanja dibatalkan lewat belanjanya.');
      }
      if (movement.reversalOfId != null) {
        throw StateError('Mutasi pembalik tidak bisa dibatalkan lagi.');
      }
      await _insertReversal(movement, reason);
      return _recompute(movement.ingredientId);
    });
  }

  // ---------------------------------------------------------- Kartu stok

  /// Kartu stok bahan, terbaru di atas (FR-1.5).
  Stream<List<StockCardEntry>> watchStockCard(String ingredientId) {
    final query = _db.select(_db.stockMovements)
      ..where((t) => t.ingredientId.equals(ingredientId));
    return query.watch().map((rows) {
      final reversed = {
        for (final r in rows)
          if (r.reversalOfId != null) r.reversalOfId!,
      };
      final sorted = [...rows]..sort(_byTime);
      return [
        for (final r in sorted.reversed)
          StockCardEntry(
            movement: r,
            cancelled: reversed.contains(r.id),
            isReversal: r.reversalOfId != null,
          ),
      ];
    });
  }

  // ------------------------------------------------- Dipakai modul lain

  /// Bahan terpakai untuk satu produksi (mutasi `PRODUCTION`). Mengembalikan
  /// biaya bahan dengan harga rata-rata pada tanggal produksi. Harus dipanggil
  /// di dalam transaksi pemanggil.
  Future<int> recordProductionUsage({
    required String productionId,
    required Map<String, Decimal> usage,
    required DateTime at,
  }) => recordUsage(
    type: MovementType.production,
    refType: 'production',
    refId: productionId,
    usage: usage,
    at: at,
  );

  /// Bahan keluar untuk satu sumber (produksi, atau pesanan pre-order yang
  /// selesai). Mengembalikan biaya bahan dengan harga rata-rata pada
  /// tanggalnya. Harus dipanggil di dalam transaksi pemanggil.
  Future<int> recordUsage({
    required MovementType type,
    required String refType,
    required String refId,
    required Map<String, Decimal> usage,
    required DateTime at,
  }) async {
    final when = at.toUtc();
    for (final MapEntry(key: ingredientId, value: qty) in usage.entries) {
      if (qty <= Decimal.zero) continue;
      await _insertMovement(
        ingredientId,
        type: type,
        qtyBase: -qty,
        refType: refType,
        refId: refId,
        occurredAt: when,
      );
    }
    await _recomputeAll(usage.keys);
    final rows =
        await (_db.select(_db.stockMovements)..where(
              (t) =>
                  t.refType.equals(refType) &
                  t.refId.equals(refId) &
                  t.reversalOfId.isNull(),
            ))
            .get();
    return rows.fold<int>(0, (sum, r) => sum - r.value);
  }

  /// Isi belanja tersimpan sebagai input form, untuk layar ubah belanja
  /// (FR-9.2).
  Future<PurchaseInput> loadPurchase(String purchaseId) async {
    final purchase = await (_db.select(
      _db.purchases,
    )..where((t) => t.id.equals(purchaseId))).getSingle();
    final items =
        await (_db.select(_db.purchaseItems)
              ..where((t) => t.purchaseId.equals(purchaseId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return PurchaseInput(
      purchasedAt: purchase.purchasedAt,
      supplierId: purchase.supplierId,
      note: purchase.note,
      cashAccountId: purchase.cashAccountId,
      lines: [
        for (final i in items)
          PurchaseLineInput(
            ingredientId: i.ingredientId,
            qty: dec(i.qty),
            unitName: i.unitName,
            factorToBase: dec(i.factorToBase),
            totalPrice: i.totalPrice,
          ),
      ],
    );
  }

  /// Harga per satuan yang dipakai [movement] saat dicatat dulu, sebelum ada
  /// koreksi sesudahnya: buku mutasi diputar ulang hanya dengan baris yang
  /// sudah ada pada waktu itu (FR-9.5).
  Future<Decimal> unitCostAsRecorded(StockMovement movement) async {
    final rows = (await _ledgerRows(movement.ingredientId))
        .where((r) => !r.createdAt.isAfter(movement.createdAt))
        .toList();
    final index = rows.indexWhere((r) => r.id == movement.id);
    if (index < 0) return dec(movement.unitCost);
    final result = replayIngredientLedger([for (final r in rows) _toLedger(r)]);
    return result.rows[index].unitCost;
  }

  /// Membalik semua mutasi bahan dari satu sumber (mis. produksi yang
  /// dibatalkan) lalu menghitung ulang bahan terkait.
  Future<void> reverseByRef(String refType, String refId, String reason) async {
    final rows =
        await (_db.select(_db.stockMovements)..where(
              (t) =>
                  t.refType.equals(refType) &
                  t.refId.equals(refId) &
                  t.reversalOfId.isNull(),
            ))
            .get();
    final ingredientIds = <String>{};
    for (final row in rows) {
      final reversed = await (_db.select(
        _db.stockMovements,
      )..where((t) => t.reversalOfId.equals(row.id))).getSingleOrNull();
      if (reversed != null) continue;
      await _insertReversal(row, reason);
      ingredientIds.add(row.ingredientId);
    }
    await _recomputeAll(ingredientIds);
  }

  // ----------------------------------------------------------- Internal

  Future<Ingredient> _recordIssueOrAdjustment(
    String ingredientId,
    MovementType type,
    Decimal qtyBase,
    String? note,
    DateTime? at,
  ) {
    if (qtyBase == Decimal.zero) {
      throw ArgumentError.value(qtyBase, 'qtyBase', 'tidak boleh 0');
    }
    return _db.transaction(() async {
      await _insertMovement(
        ingredientId,
        type: type,
        qtyBase: qtyBase,
        occurredAt: (at ?? _now()).toUtc(),
        note: note,
      );
      return _recompute(ingredientId);
    });
  }

  Future<(String, Set<String>)> _insertPurchase(
    String businessId,
    PurchaseInput input,
  ) async {
    if (input.lines.isEmpty) {
      throw ArgumentError('Belanja belum punya item.');
    }
    for (final line in input.lines) {
      if (line.qtyBase <= Decimal.zero) {
        throw ArgumentError.value(line.qty, 'qty', 'harus > 0');
      }
      if (line.totalPrice < 0) {
        throw ArgumentError.value(line.totalPrice, 'totalPrice', 'harus ≥ 0');
      }
    }
    final when = input.purchasedAt.toUtc();
    final purchase = await _db
        .into(_db.purchases)
        .insertReturning(
          PurchasesCompanion.insert(
            businessId: businessId,
            supplierId: Value(input.supplierId),
            purchasedAt: when,
            totalAmount: input.lines.fold(0, (sum, l) => sum + l.totalPrice),
            note: Value(input.note),
            cashAccountId: Value(input.cashAccountId),
          ),
        );
    final ingredientIds = <String>{};
    for (final line in input.lines) {
      final unitCost = unitCostOf(
        qtyBase: line.qtyBase,
        totalPrice: line.totalPrice,
      );
      final item = await _db
          .into(_db.purchaseItems)
          .insertReturning(
            PurchaseItemsCompanion.insert(
              purchaseId: purchase.id,
              ingredientId: line.ingredientId,
              qty: dbl(line.qty),
              unitName: line.unitName,
              factorToBase: dbl(line.factorToBase),
              qtyBase: dbl(line.qtyBase),
              totalPrice: line.totalPrice,
              unitCostBase: dbl(unitCost),
            ),
          );
      await _insertMovement(
        line.ingredientId,
        type: MovementType.purchase,
        qtyBase: line.qtyBase,
        unitCost: unitCost,
        value: line.totalPrice,
        refType: _purchaseItemRef,
        refId: item.id,
        occurredAt: when,
      );
      ingredientIds.add(line.ingredientId);
    }
    return (purchase.id, ingredientIds);
  }

  /// Mengembalikan businessId belanja dan bahan yang terkena.
  Future<(String, Set<String>)> _voidPurchase(
    String purchaseId,
    String reason,
  ) async {
    final purchase = await (_db.select(
      _db.purchases,
    )..where((t) => t.id.equals(purchaseId))).getSingle();
    if (purchase.voidedAt != null) {
      throw StateError('Belanja ini sudah dibatalkan.');
    }
    await (_db.update(
      _db.purchases,
    )..where((t) => t.id.equals(purchaseId))).write(
      PurchasesCompanion(
        voidedAt: Value(_now()),
        voidReason: Value(reason),
        updatedAt: Value(_now()),
      ),
    );
    final items = await (_db.select(
      _db.purchaseItems,
    )..where((t) => t.purchaseId.equals(purchaseId))).get();
    final ingredientIds = <String>{};
    for (final item in items) {
      final movement =
          await (_db.select(_db.stockMovements)..where(
                (t) =>
                    t.refType.equals(_purchaseItemRef) &
                    t.refId.equals(item.id) &
                    t.reversalOfId.isNull(),
              ))
              .getSingle();
      await _insertReversal(movement, reason);
      ingredientIds.add(item.ingredientId);
    }
    return (purchase.businessId, ingredientIds);
  }

  Future<void> _insertReversal(StockMovement original, String reason) async {
    final already = await (_db.select(
      _db.stockMovements,
    )..where((t) => t.reversalOfId.equals(original.id))).getSingleOrNull();
    if (already != null) {
      throw StateError('Mutasi ini sudah dibatalkan.');
    }
    await _db
        .into(_db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            ingredientId: original.ingredientId,
            type: original.type,
            qtyBase: -original.qtyBase,
            unitCost: original.unitCost,
            value: -original.value,
            balanceAfter: 0,
            avgCostAfter: 0,
            refType: Value(original.refType),
            refId: Value(original.refId),
            reversalOfId: Value(original.id),
            occurredAt: original.occurredAt,
            note: Value(reason),
          ),
        );
  }

  Future<void> _insertOpening(
    String ingredientId,
    Decimal qtyBase,
    Decimal unitCost,
    DateTime at,
  ) => _insertMovement(
    ingredientId,
    type: MovementType.opening,
    qtyBase: qtyBase,
    unitCost: unitCost,
    value: toRupiah(qtyBase * unitCost),
    occurredAt: at,
  );

  Future<void> _insertEstimate(
    String ingredientId,
    Decimal unitCost,
    DateTime at,
  ) {
    if (unitCost <= Decimal.zero) {
      throw ArgumentError.value(unitCost, 'unitCost', 'harus > 0');
    }
    return _insertMovement(
      ingredientId,
      type: MovementType.opening,
      qtyBase: Decimal.zero,
      unitCost: unitCost,
      occurredAt: at,
      note: 'Harga perkiraan',
    );
  }

  Future<void> _insertMovement(
    String ingredientId, {
    required MovementType type,
    required Decimal qtyBase,
    required DateTime occurredAt,
    Decimal? unitCost,
    int value = 0,
    String? refType,
    String? refId,
    String? note,
  }) {
    // unitCost, value, dan saldo untuk mutasi tanpa harga sendiri diisi oleh
    // _recompute.
    return _db
        .into(_db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            ingredientId: ingredientId,
            type: type,
            qtyBase: dbl(qtyBase),
            unitCost: dbl(unitCost ?? Decimal.zero),
            value: value,
            balanceAfter: 0,
            avgCostAfter: 0,
            refType: Value(refType),
            refId: Value(refId),
            occurredAt: occurredAt,
            note: Value(note),
          ),
        );
  }

  Future<void> _ensureNoPurchaseYet(String ingredientId) async {
    final rows = await _ledgerRows(ingredientId);
    final reversed = {
      for (final r in rows)
        if (r.reversalOfId != null) r.reversalOfId!,
    };
    final hasPurchase = rows.any(
      (r) =>
          r.type == MovementType.purchase &&
          r.reversalOfId == null &&
          !reversed.contains(r.id),
    );
    if (hasPurchase) {
      throw StateError(
        'Bahan ini sudah pernah dibelanjakan; stok awal dan harga perkiraan '
        'hanya untuk bahan yang belum punya belanja.',
      );
    }
  }

  /// Untuk sinkron: cache bahan dihitung ulang setelah mutasinya ditarik
  /// dari HP lain (FR-10.3).
  Future<void> recomputeIngredient(String ingredientId) =>
      _recompute(ingredientId);

  Future<void> _recomputeAll(Iterable<String> ingredientIds) async {
    for (final id in ingredientIds) {
      await _recompute(id);
    }
  }

  /// Hitung ulang seluruh buku mutasi satu bahan lalu perbarui cache-nya.
  Future<Ingredient> _recompute(String ingredientId) async {
    final rows = await _ledgerRows(ingredientId);
    final result = replayIngredientLedger([for (final r in rows) _toLedger(r)]);
    // Produksi yang biaya bahannya berubah karena koreksi harga (FR-9.5).
    final productions = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final res = result.rows[i];
      final balance = dbl(res.balanceAfter);
      final avg = dbl(res.avgCostAfter);
      if (res.cancelled) {
        // Harga dan nilai baris yang dibatalkan dibiarkan seperti dicatat.
        if (row.balanceAfter != balance || row.avgCostAfter != avg) {
          await _updateRow(row.id, balance: balance, avg: avg);
        }
        continue;
      }
      final unitCost = dbl(res.unitCost);
      if (row.refType == 'production' && row.value != res.value) {
        productions.add(row.refId!);
      }
      if (row.unitCost != unitCost ||
          row.value != res.value ||
          row.balanceAfter != balance ||
          row.avgCostAfter != avg) {
        await _updateRow(
          row.id,
          balance: balance,
          avg: avg,
          unitCost: unitCost,
          value: res.value,
        );
      }
    }

    final ingredient = await _ingredient(ingredientId);
    final avg = result.avgUnitCost;
    final low = isLowStock(
      stock: result.stock,
      minStock: dec(ingredient.minStock),
    );
    await (_db.update(
      _db.ingredients,
    )..where((t) => t.id.equals(ingredientId))).write(
      IngredientsCompanion(
        currentStock: Value(dbl(result.stock)),
        avgUnitCost: Value(avg == null ? null : dbl(avg)),
        priceIsEstimate: Value(result.priceIsEstimate),
        // Boleh diberi tahu lagi setelah stok kembali di atas minimum.
        lowStockNotified: low ? const Value.absent() : const Value(false),
        updatedAt: Value(_now()),
      ),
    );
    final newAvg = avg == null ? null : dbl(avg);
    if (ingredient.avgUnitCost != newAvg ||
        ingredient.priceIsEstimate != result.priceIsEstimate) {
      await refreshHppForIngredient(_db, ingredientId);
    }
    if (productions.isNotEmpty) {
      await refreshProductionCosts(_db, productions);
    }
    return _ingredient(ingredientId);
  }

  Future<void> _updateRow(
    String id, {
    required double balance,
    required double avg,
    double? unitCost,
    int? value,
  }) {
    return (_db.update(
      _db.stockMovements,
    )..where((t) => t.id.equals(id))).write(
      StockMovementsCompanion(
        balanceAfter: Value(balance),
        avgCostAfter: Value(avg),
        unitCost: unitCost == null ? const Value.absent() : Value(unitCost),
        value: value == null ? const Value.absent() : Value(value),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<List<StockMovement>> _ledgerRows(String ingredientId) async {
    final rows = await (_db.select(
      _db.stockMovements,
    )..where((t) => t.ingredientId.equals(ingredientId))).get();
    return rows..sort(_byTime);
  }

  Future<Ingredient> _ingredient(String id) =>
      (_db.select(_db.ingredients)..where((t) => t.id.equals(id))).getSingle();

  static LedgerMovement _toLedger(StockMovement r) => LedgerMovement(
    id: r.id,
    type: r.type,
    qtyBase: dec(r.qtyBase),
    value: r.value,
    unitCost: r.type == MovementType.opening ? dec(r.unitCost) : null,
    reversalOfId: r.reversalOfId,
  );

  /// Urutan waktu kejadian; yang dicatat lebih dulu menang bila sama.
  static int _byTime(StockMovement a, StockMovement b) {
    final byOccurred = a.occurredAt.compareTo(b.occurredAt);
    if (byOccurred != 0) return byOccurred;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }
}
