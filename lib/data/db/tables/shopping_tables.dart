import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'business_tables.dart';
import 'common.dart';
import 'stock_tables.dart';

/// Daftar belanja (FR-12.5): satu daftar aktif per usaha. Skema v4.
class ShoppingLists extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();

  /// Rentang pesanan yang dihitung: 1, 3, atau 7 hari (FR-12.1).
  IntColumn get rangeDays => integer().withDefault(const Constant(3))();

  /// Terakhir dihitung dari pesanan.
  DateTimeColumn get computedAt => dateTime().nullable()();

  /// Jumlah pesanan yang ikut dihitung saat itu (ringkasan FR-12.4).
  IntColumn get orderCount => integer().withDefault(const Constant(0))();

  /// Diisi saat Selesai belanja; kosong = daftar aktif (FR-12.9).
  DateTimeColumn get doneAt => dateTime().nullable()();
}

/// Satu baris daftar belanja: bahan, atau barang lain yang tidak masuk stok
/// (FR-12.6).
class ShoppingListItems extends Table with EntityColumns {
  TextColumn get listId =>
      text().references(ShoppingLists, #id, onDelete: KeyAction.cascade)();

  /// Kosong = barang lain (mis. plastik kemasan).
  TextColumn get ingredientId =>
      text().nullable().references(Ingredients, #id)();
  TextColumn get name => text()();

  /// Jumlah dalam [unitName]; satuan dasar = qty × [factorToBase].
  RealColumn get qty => real()();
  TextColumn get unitName => text()();
  RealColumn get factorToBase => real().withDefault(const Constant(1.0))();

  /// Perkiraan dari harga rata-rata bahan; kosong = harga belum ada.
  IntColumn get estimatedCost => integer().nullable()();
  TextColumn get source =>
      text().map(const CodedEnumConverter(ShoppingItemSource.values))();

  /// Alasan (FR-12.3): untuk pesanan dan/atau di bawah stok minimum.
  BoolColumn get forOrders => boolean().withDefault(const Constant(false))();
  BoolColumn get belowMinimum => boolean().withDefault(const Constant(false))();

  /// Dicentang = sudah dibeli (FR-12.7).
  DateTimeColumn get checkedAt => dateTime().nullable()();

  /// Belanja tempat item ini dicatat.
  TextColumn get purchaseId => text().nullable().references(Purchases, #id)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
}
