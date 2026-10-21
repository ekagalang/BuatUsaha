import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../repositories/cost_cascade.dart';
import '../repositories/hpp_refresher.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/stock_repository.dart';

/// Baris yang diterapkan dari akun dalam satu tarikan, per tabel.
class PulledChanges {
  final _rows = <String, List<Map<String, Object?>>>{};

  /// Seluruh data diganti (unduh pertama, gabung): semua cache dihitung ulang.
  bool everything = false;

  bool get isEmpty => _rows.isEmpty && !everything;

  void add(String table, Map<String, Object?> row) =>
      (_rows[table] ??= []).add(row);

  bool touched(String table) => _rows.containsKey(table);

  /// Nilai [column] dari baris [table] yang berubah.
  Set<String> ids(String table, [String column = 'id']) => {
    for (final row in _rows[table] ?? const <Map<String, Object?>>[])
      if (row[column] case final String id) id,
  };
}

/// Kolom cache tidak dikirim lewat sinkron sebagai sumber kebenaran; setelah
/// menarik, HP ini menghitungnya ulang dari buku mutasinya sendiri (FR-10.3).
class CacheRebuilder {
  CacheRebuilder(this._db) : _stock = StockRepository(_db) {
    _orders = OrderRepository(_db, _stock, ProductRepository(_db, _stock));
  }

  final AppDatabase _db;
  final StockRepository _stock;
  late final OrderRepository _orders;

  /// Riwayat HPP tidak dicatat di sini; sudah dicatat HP asalnya (FR-14.3).
  Future<void> rebuild(PulledChanges changes) async {
    if (changes.isEmpty) return;
    await withoutHppHistory(() => _rebuild(changes));
  }

  Future<void> _rebuild(PulledChanges changes) async {
    final all = changes.everything;

    // 1. Bahan: saldo dan harga rata-rata; ikut memperbarui HPP menu dan
    //    biaya produksi yang memakai bahan itu.
    final ingredients = all
        ? await _all('ingredients')
        : {
            ...changes.ids('ingredients'),
            ...changes.ids('stock_movements', 'ingredient_id'),
          };
    for (final id in await _existing('ingredients', ingredients)) {
      await _stock.recomputeIngredient(id);
    }

    // 2. Biaya bahan produksi yang ditarik.
    await refreshProductionCosts(
      _db,
      all ? await _all('productions') : changes.ids('productions'),
    );

    // 3. HPP menu: resep, biaya lain, atau upah pemilik berubah.
    final hppProducts = all || changes.touched('businesses')
        ? await _all('products')
        : {
            ...changes.ids('products'),
            ...changes.ids('recipe_items', 'product_id'),
            ...changes.ids('product_costs', 'product_id'),
          };
    for (final id in await _existing('products', hppProducts)) {
      await refreshProductHpp(_db, id);
    }

    // 4. Stok menu jadi.
    final stockProducts = all
        ? await _all('products')
        : {
            ...changes.ids('products'),
            ...changes.ids('product_stock_movements', 'product_id'),
            ...changes.ids('productions', 'product_id'),
          };
    for (final id in await _existing('products', stockProducts)) {
      await recomputeProductStock(_db, id);
    }

    // 5. Sisa tagihan pesanan.
    final orders = all
        ? await _all('orders')
        : {...changes.ids('orders'), ...changes.ids('payments', 'order_id')};
    for (final id in await _existing('orders', orders)) {
      await _orders.refreshPayment(id);
    }
  }

  Future<Set<String>> _all(String table) async {
    final rows = await _db.customSelect('SELECT id FROM $table').get();
    return {for (final r in rows) r.read<String>('id')};
  }

  Future<List<String>> _existing(String table, Set<String> ids) async {
    if (ids.isEmpty) return const [];
    final found = <String>[];
    for (final id in ids) {
      final row = await _db
          .customSelect(
            'SELECT 1 FROM $table WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull();
      if (row != null) found.add(id);
    }
    return found;
  }
}
