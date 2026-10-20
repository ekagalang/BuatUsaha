import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/enums.dart';
import 'tables/business_tables.dart';
import 'tables/common.dart';
import 'tables/order_tables.dart';
import 'tables/product_tables.dart';
import 'tables/stock_tables.dart';

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
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] diisi saat test (mis. `NativeDatabase.memory()`).
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'hpp_app',
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  Future<void>? _closing;

  /// Aman dipanggil berkali-kali, mis. saat restore lalu provider dibuang.
  Future<void> closeOnce() => _closing ??= close();

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(businesses, businesses.onboardedAt);
        await m.addColumn(expenses, expenses.isMonthly);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
