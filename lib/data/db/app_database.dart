import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/enums.dart';
import 'tables/business_tables.dart';
import 'tables/cash_tables.dart';
import 'tables/common.dart';
import 'tables/order_tables.dart';
import 'tables/pricing_tables.dart';
import 'tables/product_tables.dart';
import 'tables/shopping_tables.dart';
import 'tables/stock_tables.dart';
import 'tables/sync_tables.dart';
import '../sync/sync_schema.dart';

export '../../domain/enums.dart';

part 'app_database.g.dart';

/// Versi skema database; backup dari versi yang lebih tinggi ditolak saat
/// dipulihkan (FR-20.7).
const appSchemaVersion = 7;

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
    ProductChannelPrices,
    ProductHppHistory,
    CashAccounts,
    CashEntries,
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
  int get schemaVersion => appSchemaVersion;

  /// Penanda di `sync_state` (lokal): perbaikan stok awal data lama belum
  /// dijalankan. Waktunya = saat migrasi v7.
  static const openingFixKey = '_openingFix';

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
      if (from < 5) {
        await m.addColumn(businesses, businesses.address);
        await m.addColumn(businesses, businesses.paymentInfo);
        await m.addColumn(businesses, businesses.receiptNote);
        await m.addColumn(businesses, businesses.logoData);
        await m.addColumn(businesses, businesses.receiptSize);
      }
      if (from < 6) {
        await m.createTable(productChannelPrices);
        await m.createTable(productHppHistory);
        await m.createIndex(productHppHistoryProductTime);
        await m.createTable(cashAccounts);
        await m.createTable(cashEntries);
        await m.createIndex(cashEntriesBusinessTime);
        await m.addColumn(payments, payments.cashAccountId);
        await m.addColumn(purchases, purchases.cashAccountId);
        await m.addColumn(expenses, expenses.cashAccountId);
      }
      if (from < 7) {
        await m.addColumn(ingredients, ingredients.countUnit);
        await m.addColumn(ingredients, ingredients.archivedAt);
        await m.addColumn(products, products.archivedAt);
        await m.addColumn(recipeItems, recipeItems.unitName);
        await m.addColumn(recipeItems, recipeItems.unitFactor);
        await m.addColumn(salesChannels, salesChannels.feePerPcs);
        await m.addColumn(ingredientUnits, ingredientUnits.hidden);
        await m.addColumn(ingredientUnits, ingredientUnits.forRecipe);
        // Stok pertama yang dulu diisi lewat opname dijadikan stok awal
        // sekali, saat aplikasi berjalan dan sinkron aktif (FR-20.6).
        await into(syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(
            entity: AppDatabase.openingFixKey,
            lastPulledAt: Value(DateTime.now().toUtc()),
          ),
        );
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
