import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'common.dart';
import 'order_tables.dart';
import 'product_tables.dart';

/// Harga jual khusus satu menu di satu channel (FR-14.1). Tidak ada baris =
/// memakai harga utama menu. Skema v6.
class ProductChannelPrices extends Table with EntityColumns {
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get channelId =>
      text().references(SalesChannels, #id, onDelete: KeyAction.cascade)();
  IntColumn get price => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {productId, channelId},
  ];
}

/// Riwayat HPP per pcs (FR-14.3): hanya ditambah, dicatat oleh HP yang
/// mengubah HPP, tidak saat menerapkan data tarikan. Skema v6.
@TableIndex(
  name: 'product_hpp_history_product_time',
  columns: {#productId, #changedAt},
)
class ProductHppHistory extends Table with EntityColumns {
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();
  RealColumn get hppPerPcs => real()();

  /// Kosong untuk catatan pertama (menu baru).
  RealColumn get previousHpp => real().nullable()();
  TextColumn get cause =>
      text().map(const CodedEnumConverter(HppChangeCause.values))();

  /// Nama bahan bila sebabnya harga bahan.
  TextColumn get note => text().nullable()();
  DateTimeColumn get changedAt => dateTime()();
}
