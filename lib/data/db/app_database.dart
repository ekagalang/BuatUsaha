import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/enums.dart';
import 'tables/business_tables.dart';
import 'tables/common.dart';
import 'tables/order_tables.dart';
import 'tables/product_tables.dart';
import 'tables/shopping_tables.dart';
import 'tables/stock_tables.dart';
import 'tables/sync_tables.dart';
import '../sync/sync_schema.dart';

export '../../domain/enums.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Businesses,
    NotificationSettings,
    Ingredients,
    IngredientUnits,
    Suppliers,
    Purchases,
    PurchaseItems,
    StockMovements,
    Products,
    RecipeItems,
    ProductCosts,
    Productions,
    ProductStockMovements,
    Customers,
    SalesChannels,
    Orders,
    OrderItems,
    Payments,
    OrderReminders,
    ExpenseCategories,
    Expenses,
    ShoppingLists,
    ShoppingListItems,
    SyncOutbox,
    SyncState,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] diisi saat test (mis. `NativeDatabase.memory()`).
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'buat_usaha',
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  Future<void>? _closing;

  /// Aman dipanggil berkali-kali, mis. saat restore lalu provider dibuang.
  Future<void> closeOnce() => _closing ??= close();

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(businesses, businesses.onboardedAt);
        await m.addColumn(expenses, expenses.isMonthly);
      }
      if (from < 3) {
        await m.createTable(syncOutbox);
        await m.createTable(syncState);
        await m.addColumn(businesses, businesses.ownerUid);
      }
      if (from < 4) {
        await m.addColumn(products, products.safetyStock);
        await m.createTable(shoppingLists);
        await m.createTable(shoppingListItems);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await installSyncTriggers(this);
      // Login tersimpan dari sesi sebelumnya → pencatatan perubahan aktif.
      final owner = await customSelect(
        'SELECT 1 FROM businesses WHERE owner_uid IS NOT NULL LIMIT 1',
      ).getSingleOrNull();
      if (owner != null) await setSyncFlag(this, 'enabled', on: true);
    },
  );
}
