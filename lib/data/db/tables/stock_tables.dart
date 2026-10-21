import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'business_tables.dart';
import 'common.dart';

class Ingredients extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get category => text()
      .map(const CodedEnumConverter(IngredientCategory.values))
      .withDefault(const Constant('RAW'))();
  TextColumn get baseUnit =>
      text().map(const CodedEnumConverter(BaseUnit.values))();

  /// Ambang stok menipis, dalam satuan dasar.
  RealColumn get minStock => real().withDefault(const Constant(0.0))();

  /// Cache saldo dari [StockMovements]; bisa dihitung ulang dari ledger.
  RealColumn get currentStock => real().withDefault(const Constant(0.0))();

  /// Rp per satuan dasar, rata-rata tertimbang. Kosong = belum ada harga,
  /// sehingga HPP menu yang memakainya belum lengkap.
  RealColumn get avgUnitCost => real().nullable()();

  /// Harga masih perkiraan (FR-1.7); menjadi false setelah belanja pertama.
  BoolColumn get priceIsEstimate =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get lowStockNotified =>
      boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
}

/// Konversi satuan beli ke satuan dasar, mis. 1 pack mentega = 200 g.
class IngredientUnits extends Table with EntityColumns {
  TextColumn get ingredientId =>
      text().references(Ingredients, #id, onDelete: KeyAction.cascade)();
  TextColumn get unitName => text()();
  RealColumn get factorToBase => real()();
  BoolColumn get isDefaultPurchase =>
      boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ingredientId, unitName},
  ];
}

class Suppliers extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().nullable()();
}

class Purchases extends Table with EntityColumns, VoidColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get supplierId => text().nullable().references(Suppliers, #id)();
  DateTimeColumn get purchasedAt => dateTime()();
  IntColumn get totalAmount => integer()();
  TextColumn get note => text().nullable()();

  /// Dibayar dari akun kas ini (FR-15.2); kosong = Tunai. Skema v6.
  TextColumn get cashAccountId => text().nullable()();
}

class PurchaseItems extends Table with EntityColumns {
  TextColumn get purchaseId =>
      text().references(Purchases, #id, onDelete: KeyAction.cascade)();
  TextColumn get ingredientId => text().references(Ingredients, #id)();

  /// Qty dalam satuan beli, plus snapshot konversinya.
  RealColumn get qty => real()();
  TextColumn get unitName => text()();
  RealColumn get factorToBase => real()();

  /// qty × factorToBase.
  RealColumn get qtyBase => real()();
  IntColumn get totalPrice => integer()();

  /// totalPrice / qtyBase.
  RealColumn get unitCostBase => real()();
}

/// Buku mutasi stok: satu-satunya jalan stok bahan berubah.
@TableIndex(
  name: 'stock_movements_ingredient_time',
  columns: {#ingredientId, #occurredAt},
)
class StockMovements extends Table with EntityColumns {
  TextColumn get ingredientId => text().references(Ingredients, #id)();
  TextColumn get type =>
      text().map(const CodedEnumConverter(MovementType.values))();

  /// Positif = masuk, negatif = keluar.
  RealColumn get qtyBase => real()();
  RealColumn get unitCost => real()();

  /// qtyBase × unitCost, dibulatkan ke Rupiah.
  IntColumn get value => integer()();
  RealColumn get balanceAfter => real()();
  RealColumn get avgCostAfter => real()();

  /// Sumber mutasi: `purchase_item`, `production`, `order`; kosong untuk stok
  /// awal dan penyesuaian manual.
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();

  /// Diisi pada mutasi pembalik: id mutasi yang dibatalkan (FR-9.1).
  TextColumn get reversalOfId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
}
