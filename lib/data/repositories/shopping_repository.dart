import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/money.dart';
import '../../domain/stock/units.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'order_repository.dart';
import 'stock_repository.dart' show IngredientUnitLabel;

/// Satu bahan yang perlu dibeli (FR-12.2, FR-12.3).
class ShoppingSuggestion {
  const ShoppingSuggestion({
    required this.ingredient,
    required this.requiredQty,
    required this.shortage,
    required this.unit,
    required this.unitQty,
    required this.forOrders,
    required this.belowMinimum,
  });

  final Ingredient ingredient;

  /// Kebutuhan pesanan dalam satuan dasar.
  final Decimal requiredQty;

  /// Kebutuhan + stok minimum − stok sekarang, sebelum dibulatkan.
  final Decimal shortage;

  /// Satuan beli bawaan bahan, atau satuan dasar.
  final UnitOption unit;

  /// Jumlah dalam [unit], dibulatkan ke atas.
  final Decimal unitQty;
  final bool forOrders;
  final bool belowMinimum;

  Decimal get baseQty => unitQty * unit.factorToBase;

  /// Perkiraan dari harga rata-rata; `null` = bahan belum punya harga.
  int? get estimatedCost => ingredient.avgUnitCost == null
      ? null
      : toRupiah(baseQty * dec(ingredient.avgUnitCost!));
}

/// Hasil hitungan kebutuhan belanja untuk satu rentang.
class ShoppingPlan {
  const ShoppingPlan({
    required this.items,
    required this.orderCount,
    required this.until,
  });

  final List<ShoppingSuggestion> items;
  final int orderCount;

  /// Hari terakhir rentang (lokal).
  final DateTime until;

  int get total => items.fold(0, (sum, i) => sum + (i.estimatedCost ?? 0));
}

/// Item daftar beserta bahannya (kosong untuk barang lain).
class ShoppingLine {
  const ShoppingLine({required this.item, this.ingredient});

  final ShoppingListItem item;
  final Ingredient? ingredient;

  bool get isOther => item.ingredientId == null;
  bool get checked => item.checkedAt != null;
  bool get recorded => item.purchaseId != null;
}

class ShoppingListView {
  const ShoppingListView({required this.list, required this.lines});

  final ShoppingList list;
  final List<ShoppingLine> lines;

  List<ShoppingLine> get todo => lines.where((l) => !l.checked).toList();
  List<ShoppingLine> get done => lines.where((l) => l.checked).toList();

  /// Dicentang, berupa bahan, dan belum tercatat di belanja (FR-12.7).
  List<ShoppingLine> get toRecord =>
      lines.where((l) => l.checked && !l.recorded && !l.isOther).toList();

  int get total => lines.fold(0, (sum, l) => sum + (l.item.estimatedCost ?? 0));
  int get ingredientCount => lines.where((l) => !l.isOther).length;
  int get otherCount => lines.where((l) => l.isOther).length;

  /// Hari terakhir rentang saat terakhir dihitung.
  DateTime? get until {
    final at = list.computedAt?.toLocal();
    if (at == null) return null;
    final day = DateTime(at.year, at.month, at.day);
    return day.add(Duration(days: list.rangeDays - 1));
  }
}

/// Daftar belanja dari pesanan mendatang (PRD FR-12).
class ShoppingRepository {
  ShoppingRepository(this._db, this._orders);

  final AppDatabase _db;
  final OrderRepository _orders;

  static DateTime _now() => DateTime.now().toUtc();

  // ------------------------------------------------------------- Hitungan

  /// Yang perlu dibeli untuk pesanan hari ini sampai [days] hari ke depan.
  Future<ShoppingPlan> plan(
    String businessId,
    int days, {
    DateTime? now,
  }) async {
    final local = (now ?? DateTime.now()).toLocal();
    final from = DateTime(local.year, local.month, local.day);
    final to = from.add(Duration(days: days));
    final needs = await _orders.productionNeedsBetween(
      businessId,
      from,
      to,
      safetyStock: true,
    );
    final required = {
      for (final n in needs.ingredients) n.ingredient.id: n.requiredQty,
    };
    final ingredients =
        await (_db.select(_db.ingredients)
              ..where(
                (t) => t.businessId.equals(businessId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    final units = await _db.select(_db.ingredientUnits).get();
    final items = <ShoppingSuggestion>[];
    for (final ingredient in ingredients) {
      final need = required[ingredient.id] ?? Decimal.zero;
      final stock = _floor0(dec(ingredient.currentStock));
      // Bahan yang diarsipkan hanya masuk bila masih dibutuhkan pesanan.
      final minimum = ingredient.archivedAt == null
          ? dec(ingredient.minStock)
          : Decimal.zero;
      final shortage = need + minimum - stock;
      if (shortage <= Decimal.zero) continue;
      final unit = purchaseUnitFor(ingredient, [
        for (final u in units)
          if (u.ingredientId == ingredient.id) u,
      ]);
      items.add(
        ShoppingSuggestion(
          ingredient: ingredient,
          requiredQty: need,
          shortage: shortage,
          unit: unit,
          unitQty: _roundUp(shortage, unit.factorToBase),
          forOrders: need > stock,
          belowMinimum: minimum > Decimal.zero && stock - need < minimum,
        ),
      );
    }
    return ShoppingPlan(
      items: items,
      orderCount: needs.orderCount,
      until: to.subtract(const Duration(days: 1)),
    );
  }

  /// Berubah setiap pesanan, menu, atau bahan berubah (kartu Beranda dan
  /// Bahan, FR-12.11).
  Stream<ShoppingPlan> watchPlan(String businessId, int days) async* {
    Future<ShoppingPlan> load() => plan(businessId, days);
    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.orders,
        _db.orderItems,
        _db.products,
        _db.recipeItems,
        _db.productions,
        _db.ingredients,
        _db.ingredientUnits,
      ]),
    )) {
      yield await load();
    }
  }

  /// Satuan beli bawaan: konversi khusus yang ditandai bawaan, konversi
  /// khusus pertama, atau satuan dasar.
  static UnitOption purchaseUnitFor(
    Ingredient ingredient,
    List<IngredientUnit> units,
  ) {
    final sorted = [...units]
      ..sort((a, b) {
        if (a.isDefaultPurchase != b.isDefaultPurchase) {
          return a.isDefaultPurchase ? -1 : 1;
        }
        return a.unitName.compareTo(b.unitName);
      });
    final first = sorted.firstOrNull;
    if (first == null) {
      return UnitOption(name: ingredient.unitLabel, factorToBase: Decimal.one);
    }
    return UnitOption(
      name: first.unitName,
      factorToBase: dec(first.factorToBase),
      isCustom: true,
    );
  }

  static Decimal _roundUp(Decimal qty, Decimal factor) {
    final units = divide(qty, factor).ceil();
    return units < Decimal.one ? Decimal.one : units;
  }

  static Decimal _floor0(Decimal v) => v < Decimal.zero ? Decimal.zero : v;

  // ---------------------------------------------------------------- Daftar

  /// Daftar aktif usaha; dibuat bila belum ada. Bila dua HP sempat membuat
  /// daftar sendiri, yang terbaru dipakai.
  Future<ShoppingList> activeList(String businessId) async {
    final existing = await _activeQuery(businessId).getSingleOrNull();
    if (existing != null) return existing;
    return _db
        .into(_db.shoppingLists)
        .insertReturning(ShoppingListsCompanion.insert(businessId: businessId));
  }

  SimpleSelectStatement<$ShoppingListsTable, ShoppingList> _activeQuery(
    String businessId,
  ) => _db.select(_db.shoppingLists)
    ..where((t) => t.businessId.equals(businessId) & t.doneAt.isNull())
    ..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ])
    ..limit(1);

  Stream<ShoppingListView?> watchActive(String businessId) async* {
    Future<ShoppingListView?> load() async {
      final list = await _activeQuery(businessId).getSingleOrNull();
      return list == null ? null : view(list.id);
    }

    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.shoppingLists,
        _db.shoppingListItems,
        _db.ingredients,
      ]),
    )) {
      yield await load();
    }
  }

  Future<ShoppingListView> view(String listId) async {
    final list = await (_db.select(
      _db.shoppingLists,
    )..where((t) => t.id.equals(listId))).getSingle();
    final rows =
        await (_db.select(_db.shoppingListItems).join([
                leftOuterJoin(
                  _db.ingredients,
                  _db.ingredients.id.equalsExp(
                    _db.shoppingListItems.ingredientId,
                  ),
                ),
              ])
              ..where(_db.shoppingListItems.listId.equals(listId))
              ..orderBy([
                OrderingTerm.asc(_db.shoppingListItems.position),
                OrderingTerm.asc(_db.shoppingListItems.createdAt),
              ]))
            .get();
    return ShoppingListView(
      list: list,
      lines: [
        for (final r in rows)
          ShoppingLine(
            item: r.readTable(_db.shoppingListItems),
            ingredient: r.readTableOrNull(_db.ingredients),
          ),
      ],
    );
  }

  /// Hitung ulang dari pesanan (FR-12.5): item otomatis yang belum
  /// dicentang diperbarui atau dihapus; item sendiri, dicentang, atau
  /// tercatat tidak diubah.
  Future<void> recalculate(String listId, {int? days, DateTime? now}) {
    return _db.transaction(() async {
      final list = await (_db.select(
        _db.shoppingLists,
      )..where((t) => t.id.equals(listId))).getSingle();
      final range = days ?? list.rangeDays;
      final plan = await this.plan(list.businessId, range, now: now);
      final items = await (_db.select(
        _db.shoppingListItems,
      )..where((t) => t.listId.equals(listId))).get();
      bool editable(ShoppingListItem i) =>
          i.source == ShoppingItemSource.auto &&
          i.checkedAt == null &&
          i.purchaseId == null;
      final auto = {
        for (final i in items.where(editable))
          if (i.ingredientId != null) i.ingredientId!: i,
      };
      final owned = {
        for (final i in items.where((i) => !editable(i)))
          if (i.ingredientId != null) i.ingredientId!,
      };
      var position = items.fold(
        0,
        (max, i) => i.position > max ? i.position : max,
      );
      final wanted = <String>{};
      for (final s in plan.items) {
        final id = s.ingredient.id;
        if (owned.contains(id)) continue;
        wanted.add(id);
        final values = ShoppingListItemsCompanion(
          name: Value(s.ingredient.name),
          qty: Value(dbl(s.unitQty)),
          unitName: Value(s.unit.name),
          factorToBase: Value(dbl(s.unit.factorToBase)),
          estimatedCost: Value(s.estimatedCost),
          forOrders: Value(s.forOrders),
          belowMinimum: Value(s.belowMinimum),
          updatedAt: Value(_now()),
        );
        final current = auto[id];
        if (current == null) {
          await _db
              .into(_db.shoppingListItems)
              .insert(
                values.copyWith(
                  listId: Value(listId),
                  ingredientId: Value(id),
                  source: const Value(ShoppingItemSource.auto),
                  position: Value(++position),
                ),
              );
        } else if (_differs(current, s)) {
          await (_db.update(
            _db.shoppingListItems,
          )..where((t) => t.id.equals(current.id))).write(values);
        }
      }
      for (final stale in auto.values) {
        if (!wanted.contains(stale.ingredientId)) {
          await (_db.delete(
            _db.shoppingListItems,
          )..where((t) => t.id.equals(stale.id))).go();
        }
      }
      await (_db.update(
        _db.shoppingLists,
      )..where((t) => t.id.equals(listId))).write(
        ShoppingListsCompanion(
          rangeDays: Value(range),
          computedAt: Value((now ?? DateTime.now()).toUtc()),
          orderCount: Value(plan.orderCount),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  static bool _differs(ShoppingListItem i, ShoppingSuggestion s) =>
      i.qty != dbl(s.unitQty) ||
      i.unitName != s.unit.name ||
      i.factorToBase != dbl(s.unit.factorToBase) ||
      i.estimatedCost != s.estimatedCost ||
      i.forOrders != s.forOrders ||
      i.belowMinimum != s.belowMinimum ||
      i.name != s.ingredient.name;

  /// Tambah bahan sendiri (FR-12.6): satuan beli bawaan, jumlah 1.
  Future<void> addIngredient(String listId, String ingredientId) async {
    final ingredient = await (_db.select(
      _db.ingredients,
    )..where((t) => t.id.equals(ingredientId))).getSingle();
    final units = await (_db.select(
      _db.ingredientUnits,
    )..where((t) => t.ingredientId.equals(ingredientId))).get();
    final unit = purchaseUnitFor(ingredient, units);
    await _insertManual(
      listId,
      ShoppingListItemsCompanion.insert(
        listId: listId,
        ingredientId: Value(ingredientId),
        name: ingredient.name,
        qty: 1,
        unitName: unit.name,
        factorToBase: Value(dbl(unit.factorToBase)),
        estimatedCost: Value(_estimate(ingredient, Decimal.one, unit)),
        source: ShoppingItemSource.manual,
      ),
    );
  }

  /// Barang lain yang tidak masuk stok bahan (FR-12.6).
  Future<void> addOther(
    String listId,
    String name, {
    double qty = 1,
    String unitName = 'pcs',
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Nama barang belum diisi.');
    return _insertManual(
      listId,
      ShoppingListItemsCompanion.insert(
        listId: listId,
        name: trimmed,
        qty: qty,
        unitName: unitName,
        source: ShoppingItemSource.manual,
      ),
    );
  }

  Future<void> _insertManual(
    String listId,
    ShoppingListItemsCompanion item,
  ) async {
    final max = _db.shoppingListItems.position.max();
    final row =
        await (_db.selectOnly(_db.shoppingListItems)
              ..addColumns([max])
              ..where(_db.shoppingListItems.listId.equals(listId)))
            .getSingle();
    await _db
        .into(_db.shoppingListItems)
        .insert(item.copyWith(position: Value((row.read(max) ?? 0) + 1)));
  }

  /// Ubah jumlah/satuan (FR-12.5); item jadi milik pengguna sehingga tidak
  /// diubah Hitung ulang.
  Future<void> updateItem(String itemId, Decimal qty, UnitOption unit) async {
    if (qty <= Decimal.zero) throw ArgumentError.value(qty, 'qty', 'harus > 0');
    final item = await _item(itemId);
    Ingredient? ingredient;
    if (item.ingredientId != null) {
      ingredient = await (_db.select(
        _db.ingredients,
      )..where((t) => t.id.equals(item.ingredientId!))).getSingle();
    }
    await (_db.update(
      _db.shoppingListItems,
    )..where((t) => t.id.equals(itemId))).write(
      ShoppingListItemsCompanion(
        qty: Value(dbl(qty)),
        unitName: Value(unit.name),
        factorToBase: Value(dbl(unit.factorToBase)),
        estimatedCost: Value(
          ingredient == null ? null : _estimate(ingredient, qty, unit),
        ),
        source: const Value(ShoppingItemSource.manual),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<void> removeItem(String itemId) => (_db.delete(
    _db.shoppingListItems,
  )..where((t) => t.id.equals(itemId))).go();

  /// Centang = sudah dibeli. Item yang sudah tercatat di belanja tidak bisa
  /// dibatalkan centangnya.
  Future<void> setChecked(String itemId, {required bool checked}) async {
    final item = await _item(itemId);
    if (item.purchaseId != null) {
      throw StateError('Sudah dicatat di belanja; ubah lewat belanja itu.');
    }
    await (_db.update(
      _db.shoppingListItems,
    )..where((t) => t.id.equals(itemId))).write(
      ShoppingListItemsCompanion(
        checkedAt: Value(checked ? _now() : null),
        updatedAt: Value(_now()),
      ),
    );
  }

  /// Item yang dicatat lewat form Belanja (FR-12.7).
  Future<void> markRecorded(List<String> itemIds, String purchaseId) async {
    await (_db.update(
      _db.shoppingListItems,
    )..where((t) => t.id.isIn(itemIds))).write(
      ShoppingListItemsCompanion(
        purchaseId: Value(purchaseId),
        checkedAt: Value(_now()),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<List<ShoppingLine>> linesToRecord(String listId) async =>
      (await view(listId)).toRecord;

  /// Selesai belanja (FR-12.9).
  Future<void> finish(String listId) =>
      (_db.update(_db.shoppingLists)..where((t) => t.id.equals(listId))).write(
        ShoppingListsCompanion(doneAt: Value(_now()), updatedAt: Value(_now())),
      );

  Future<ShoppingListItem> _item(String id) => (_db.select(
    _db.shoppingListItems,
  )..where((t) => t.id.equals(id))).getSingle();

  static int? _estimate(Ingredient ingredient, Decimal qty, UnitOption unit) {
    final avg = ingredient.avgUnitCost;
    if (avg == null) return null;
    return toRupiah(qty * unit.factorToBase * dec(avg));
  }
}
