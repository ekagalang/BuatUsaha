import 'package:drift/drift.dart';

/// Tabel bisnis yang disinkron ke Firestore, urut induk → anak supaya foreign
/// key terpenuhi saat data ditarik (PRD 11.5).
const syncedTables = [
  'businesses',
  'notification_settings',
  'expense_categories',
  'suppliers',
  'ingredients',
  'ingredient_units',
  'products',
  'recipe_items',
  'product_costs',
  'customers',
  'sales_channels',
  'purchases',
  'purchase_items',
  'shopping_lists',
  'shopping_list_items',
  'orders',
  'order_items',
  'payments',
  'order_reminders',
  'productions',
  'stock_movements',
  'product_stock_movements',
  'expenses',
];

/// Kolom cache per tabel: dihitung ulang dari buku mutasi di tiap HP, jadi
/// perubahan kolom ini saja tidak memicu kiriman (FR-10.3). Nilainya tetap
/// ikut terkirim bersama barisnya (kolom NOT NULL) lalu ditimpa hasil hitung
/// ulang di HP penerima. `updated_at` ikut berubah setiap cache diperbarui,
/// jadi juga tidak memicu.
const cacheColumns = <String, Set<String>>{
  'ingredients': {'current_stock', 'avg_unit_cost', 'price_is_estimate'},
  'stock_movements': {'unit_cost', 'value', 'balance_after', 'avg_cost_after'},
  'products': {
    'hpp_per_pcs',
    'hpp_status',
    'hpp_updated_at',
    'current_stock',
    'stock_unit_cost',
  },
  'product_stock_movements': {
    'unit_cost',
    'value',
    'balance_after',
    'avg_cost_after',
  },
  'productions': {'material_cost', 'hpp_per_pcs'},
  'orders': {'paid_amount', 'payment_status'},
};

/// Kolom yang hanya berlaku di HP ini: tidak dikirim, tidak ditimpa saat
/// menarik, dan tidak memicu kiriman.
const localOnlyColumns = <String, Set<String>>{
  'businesses': {'owner_uid'},
  'ingredients': {'low_stock_notified'},
  // Id jadwal di flutter_local_notifications, dibuat sendiri di tiap HP.
  'order_reminders': {'notification_id'},
};

/// Kunci unik selain `id`. Dua HP yang offline bisa membuat baris berbeda
/// dengan kunci yang sama; mesin sinkron menyelesaikannya saat menarik.
const uniqueKeys = <String, List<String>>{
  'notification_settings': ['business_id'],
  'ingredient_units': ['ingredient_id', 'unit_name'],
  'recipe_items': ['product_id', 'ingredient_id'],
  'orders': ['business_id', 'order_no'],
};

/// Waktu sekarang dalam milidetik epoch, dihitung di SQLite.
const _nowMs = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";

/// Trigger sementara (per koneksi) yang mencatat setiap baris yang berubah ke
/// `sync_outbox`. Hanya aktif setelah login (bendera `enabled`) dan tidak
/// aktif saat data dari Firestore sedang diterapkan (bendera `applying`).
Future<void> installSyncTriggers(DatabaseConnectionUser db) async {
  await db.customStatement(
    'CREATE TEMP TABLE IF NOT EXISTS sync_flags (name TEXT PRIMARY KEY)',
  );
  const when =
      "EXISTS (SELECT 1 FROM temp.sync_flags WHERE name = 'enabled') AND "
      "NOT EXISTS (SELECT 1 FROM temp.sync_flags WHERE name = 'applying')";
  for (final table in syncedTables) {
    final columns = await tableColumns(db, table);
    final skip = {
      ...?cacheColumns[table],
      ...?localOnlyColumns[table],
      'updated_at',
    };
    final watched = columns.where((c) => !skip.contains(c)).join(', ');
    String enqueue(String row) =>
        "INSERT OR REPLACE INTO main.sync_outbox (table_name, row_id, changed_at) "
        "VALUES ('$table', $row.id, $_nowMs);";
    await db.customStatement(
      'CREATE TEMP TRIGGER IF NOT EXISTS sync_${table}_insert AFTER INSERT ON '
      'main.$table WHEN $when BEGIN ${enqueue('NEW')} END',
    );
    await db.customStatement(
      'CREATE TEMP TRIGGER IF NOT EXISTS sync_${table}_update AFTER UPDATE OF '
      '$watched ON main.$table WHEN $when BEGIN ${enqueue('NEW')} END',
    );
    await db.customStatement(
      'CREATE TEMP TRIGGER IF NOT EXISTS sync_${table}_delete AFTER DELETE ON '
      'main.$table WHEN $when BEGIN ${enqueue('OLD')} END',
    );
  }
}

Future<List<String>> tableColumns(
  DatabaseConnectionUser db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA main.table_info($table)').get();
  return [for (final r in rows) r.read<String>('name')];
}

Future<void> setSyncFlag(
  DatabaseConnectionUser db,
  String name, {
  required bool on,
}) => db.customStatement(
  on
      ? 'INSERT OR IGNORE INTO temp.sync_flags (name) VALUES (?)'
      : 'DELETE FROM temp.sync_flags WHERE name = ?',
  [name],
);
