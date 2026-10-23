import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'business_tables.dart';
import 'common.dart';
import 'order_tables.dart';
import 'stock_tables.dart';

/// Menu yang dijual. Di UI disebut "menu", di skema tetap `products`.
class Products extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get category => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  IntColumn get sellingPrice => integer()();

  /// Hasil pcs per 1 resep.
  RealColumn get yieldQty => real()();

  /// Menimpa markup bawaan usaha jika diisi.
  RealColumn get targetMarkupPct => real().nullable()();

  /// Kosong = ikut mode stok bawaan usaha.
  TextColumn get stockDeductMode =>
      text().nullable().map(const CodedEnumConverter(StockDeductMode.values))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Cache HPP terkini; dihitung ulang saat harga bahan atau resep berubah.
  RealColumn get hppPerPcs => real().withDefault(const Constant(0.0))();
  DateTimeColumn get hppUpdatedAt => dateTime().nullable()();
  TextColumn get hppStatus => text()
      .map(const CodedEnumConverter(HppStatus.values))
      .withDefault(const Constant('INCOMPLETE'))();

  /// Cache saldo stok produk jadi dari [ProductStockMovements].
  RealColumn get currentStock => real().withDefault(const Constant(0.0))();

  /// HPP rata-rata tertimbang stok produk jadi.
  RealColumn get stockUnitCost => real().withDefault(const Constant(0.0))();

  /// Umur simpan dalam hari untuk produk ready stock (FR-4.10).
  IntColumn get shelfLifeDays => integer().nullable()();

  /// Stok jaga: pcs yang ingin selalu tersedia, ikut dihitung di daftar
  /// belanja (FR-12.10). Skema v4.
  RealColumn get safetyStock => real().withDefault(const Constant(0.0))();

  /// Diarsipkan: disembunyikan dari daftar dan pilihan, bisa dipulihkan
  /// (FR-20.4). Dihapus padahal punya riwayat memakai `deletedAt`. Skema v7.
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

/// Takaran bahan per 1 resep (bill of materials).
class RecipeItems extends Table with EntityColumns {
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get ingredientId => text().references(Ingredients, #id)();
  RealColumn get qtyBase => real()();

  /// Satuan takaran yang diketik (mis. sdm) dan faktornya ke satuan dasar;
  /// kosong = satuan dasar (FR-20.3). Skema v7.
  TextColumn get unitName => text().nullable()();
  RealColumn get unitFactor => real().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {productId, ingredientId},
  ];
}

/// Biaya yang tidak punya stok: gas, listrik, tenaga kerja, penyusutan alat.
class ProductCosts extends Table with EntityColumns {
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get costType =>
      text().map(const CodedEnumConverter(CostType.values))();
  IntColumn get amount => integer()();
  TextColumn get basis =>
      text().map(const CodedEnumConverter(CostBasis.values))();

  /// Khusus upah pemilik: jam kerja per resep; amount = jam × upah per jam.
  RealColumn get laborHours => real().nullable()();
}

class Productions extends Table with EntityColumns, VoidColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get orderId => text().nullable().references(Orders, #id)();

  /// Jumlah resep (boleh desimal) dan hasil pcs.
  RealColumn get batchQty => real()();
  RealColumn get outputQty => real()();
  IntColumn get materialCost => integer()();
  IntColumn get otherCost => integer()();

  /// Snapshot HPP saat produksi.
  RealColumn get hppPerPcs => real()();
  DateTimeColumn get producedAt => dateTime()();
  TextColumn get note => text().nullable()();
}

/// Buku mutasi stok produk jadi: satu-satunya jalan stok menu ready stock
/// berubah.
@TableIndex(
  name: 'product_stock_movements_product_time',
  columns: {#productId, #occurredAt},
)
class ProductStockMovements extends Table with EntityColumns {
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get type =>
      text().map(const CodedEnumConverter(ProductMovementType.values))();

  /// Pcs; positif = masuk, negatif = keluar.
  RealColumn get qty => real()();

  /// HPP per pcs yang dipakai mutasi ini; stok awal memakai HPP terkini.
  RealColumn get unitCost => real()();

  /// qty × unitCost, dibulatkan ke Rupiah.
  IntColumn get value => integer()();
  RealColumn get balanceAfter => real()();
  RealColumn get avgCostAfter => real()();

  /// Untuk `WASTE`: alasan dibuang.
  TextColumn get reason =>
      text().nullable().map(const CodedEnumConverter(WasteReason.values))();

  /// Sumber: `production`, `order`, atau `day_close` (refId = tanggal ditutup).
  TextColumn get refType => text().nullable()();
  TextColumn get refId => text().nullable()();

  /// Diisi pada mutasi pembalik: id mutasi yang dibatalkan (FR-9.1).
  TextColumn get reversalOfId => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
}
