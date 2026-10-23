import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notifications.dart';
import '../services/notification_sync.dart';
import 'db/app_database.dart';
import 'db/database_provider.dart';
import 'repositories/archive_repository.dart';
import 'repositories/business_repository.dart';
import 'repositories/cash_repository.dart';
import 'repositories/day_close_repository.dart';
import 'repositories/expense_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/pricing_repository.dart';
import 'repositories/product_repository.dart';
import 'repositories/purchase_preview.dart';
import 'repositories/report_repository.dart';
import 'repositories/shopping_repository.dart';
import 'repositories/stock_repository.dart';

export 'db/database_provider.dart';

final businessRepositoryProvider = Provider(
  (ref) => BusinessRepository(ref.watch(appDatabaseProvider)),
);

final stockRepositoryProvider = Provider(
  (ref) => StockRepository(ref.watch(appDatabaseProvider)),
);

/// Usaha aktif (MVP: satu usaha, dibuat otomatis).
final currentBusinessProvider = FutureProvider<Business>(
  (ref) => ref.watch(businessRepositoryProvider).ensureDefault(),
);

final ingredientsProvider = StreamProvider<List<IngredientView>>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(stockRepositoryProvider).watchIngredients(business.id);
});

final ingredientProvider = StreamProvider.family<IngredientView, String>(
  (ref, id) => ref.watch(stockRepositoryProvider).watchIngredient(id),
);

final stockCardProvider = StreamProvider.family<List<StockCardEntry>, String>(
  (ref, id) => ref.watch(stockRepositoryProvider).watchStockCard(id),
);

/// Usaha aktif yang selalu terbaru (upah per jam, markup bawaan, dst.).
final businessProvider = StreamProvider<Business>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(businessRepositoryProvider).watch(business.id);
});

final productRepositoryProvider = Provider(
  (ref) => ProductRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(stockRepositoryProvider),
  ),
);

final productsProvider = StreamProvider<List<ProductView>>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(productRepositoryProvider).watchProducts(business.id);
});

final productProvider = StreamProvider.family<ProductView, String>(
  (ref, id) => ref.watch(productRepositoryProvider).watchProduct(id),
);

final productionsProvider = StreamProvider.family<List<Production>, String>(
  (ref, id) => ref.watch(productRepositoryProvider).watchProductions(id),
);

final orderRepositoryProvider = Provider(
  (ref) => OrderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(stockRepositoryProvider),
    ref.watch(productRepositoryProvider),
  ),
);

final dayCloseRepositoryProvider = Provider(
  (ref) => DayCloseRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(productRepositoryProvider),
  ),
);

/// Sinkron jadwal notifikasi; dimulai di `main`, tidak di test.
final notificationSyncProvider = Provider((ref) {
  final sync = NotificationSync(
    ref.watch(appDatabaseProvider),
    LocalNotifications.instance,
  );
  ref.onDispose(sync.dispose);
  return sync;
});

/// Pesanan dengan jadwal di rentang `[from, to)`.
final ordersInRangeProvider =
    StreamProvider.family<List<OrderView>, (DateTime, DateTime)>((
      ref,
      range,
    ) async* {
      final business = await ref.watch(currentBusinessProvider.future);
      yield* ref
          .watch(orderRepositoryProvider)
          .watchOrders(business.id, from: range.$1, to: range.$2);
    });

final orderProvider = StreamProvider.family<OrderView, String>(
  (ref, id) => ref.watch(orderRepositoryProvider).watchOrder(id),
);

final channelsProvider = StreamProvider<List<SalesChannel>>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(orderRepositoryProvider).watchChannels(business.id);
});

final notificationSettingsProvider = StreamProvider<NotificationSetting>((
  ref,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref
      .watch(businessRepositoryProvider)
      .watchNotificationSettings(business.id);
});

/// Kebutuhan produksi untuk satu tanggal lokal (FR-5.5).
final productionNeedsProvider =
    StreamProvider.family<ProductionNeeds, DateTime>((ref, day) async* {
      final business = await ref.watch(currentBusinessProvider.future);
      yield* ref
          .watch(orderRepositoryProvider)
          .watchProductionNeeds(business.id, day);
    });

final expenseRepositoryProvider = Provider(
  (ref) => ExpenseRepository(ref.watch(appDatabaseProvider)),
);

final reportRepositoryProvider = Provider(
  (ref) => ReportRepository(ref.watch(appDatabaseProvider)),
);

/// Ringkasan untung/rugi satu tanggal lokal (FR-7.6).
final dayReportProvider = StreamProvider.family<DayReport, DateTime>((
  ref,
  day,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(reportRepositoryProvider).watchDay(business.id, day);
});

/// Laporan periode `[from, to)` (FR-7.5).
final periodReportProvider =
    StreamProvider.family<PeriodReport, (DateTime, DateTime)>((
      ref,
      range,
    ) async* {
      final business = await ref.watch(currentBusinessProvider.future);
      yield* ref
          .watch(reportRepositoryProvider)
          .watchPeriod(business.id, range.$1, range.$2);
    });

final expensesProvider =
    StreamProvider.family<List<ExpenseView>, (DateTime, DateTime)>((
      ref,
      range,
    ) async* {
      final business = await ref.watch(currentBusinessProvider.future);
      yield* ref
          .watch(expenseRepositoryProvider)
          .watchExpenses(business.id, from: range.$1, to: range.$2);
    });

final expenseCategoriesProvider = StreamProvider<List<ExpenseCategory>>((
  ref,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(expenseRepositoryProvider).watchCategories(business.id);
});

/// Sisa menu ready stock untuk Tutup hari hari ini, ikut berubah saat stok
/// menu berubah.
final leftoversProvider = StreamProvider<List<Leftover>>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  final db = ref.watch(appDatabaseProvider);
  final repo = ref.watch(dayCloseRepositoryProvider);
  yield await repo.leftovers(business.id, DateTime.now());
  await for (final _ in db.tableUpdates(
    TableUpdateQuery.onAllTables([db.products, db.productStockMovements]),
  )) {
    yield await repo.leftovers(business.id, DateTime.now());
  }
});

final productCardProvider =
    StreamProvider.family<List<ProductStockMovement>, String>(
      (ref, id) => ref.watch(productRepositoryProvider).watchProductCard(id),
    );

/// Pesanan selesai yang HPP-nya berubah karena koreksi harga bahan (FR-9.5).
final costCorrectionsProvider = StreamProvider<List<OrderCorrection>>((
  ref,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(orderRepositoryProvider).watchCostCorrections(business.id);
});

final purchasePreviewerProvider = Provider(
  (ref) => PurchasePreviewer(
    ref.watch(appDatabaseProvider),
    ref.watch(stockRepositoryProvider),
    ref.watch(orderRepositoryProvider),
  ),
);

final shoppingRepositoryProvider = Provider(
  (ref) => ShoppingRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(orderRepositoryProvider),
  ),
);

/// Daftar belanja aktif usaha (FR-12.5); `null` bila belum pernah dibuka.
final activeShoppingListProvider = StreamProvider<ShoppingListView?>((
  ref,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(shoppingRepositoryProvider).watchActive(business.id);
});

/// Yang perlu dibeli untuk pesanan [days] hari ke depan (kartu Beranda dan
/// Bahan, FR-12.11).
final shoppingPlanProvider = StreamProvider.family<ShoppingPlan, int>((
  ref,
  days,
) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(shoppingRepositoryProvider).watchPlan(business.id, days);
});

final pricingRepositoryProvider = Provider(
  (ref) => PricingRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(productRepositoryProvider),
  ),
);

/// Harga khusus per menu per channel (FR-14.1).
final channelPricesProvider = StreamProvider<ChannelPrices>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(pricingRepositoryProvider).watchChannelPrices(business.id);
});

final channelPriceRowsProvider =
    StreamProvider.family<List<ChannelPriceRow>, String>(
      (ref, productId) =>
          ref.watch(pricingRepositoryProvider).watchChannelRows(productId),
    );

final hppHistoryProvider =
    StreamProvider.family<List<ProductHppHistoryData>, String>(
      (ref, productId) =>
          ref.watch(pricingRepositoryProvider).watchHppHistory(productId),
    );

final cashRepositoryProvider = Provider(
  (ref) => CashRepository(ref.watch(appDatabaseProvider)),
);

final cashAccountsProvider = StreamProvider<List<CashAccount>>((ref) async* {
  final business = await ref.watch(currentBusinessProvider.future);
  yield* ref.watch(cashRepositoryProvider).watchAccounts(business.id);
});

/// Kas periode `[from, to)` (FR-15.4).
final cashPeriodProvider =
    StreamProvider.family<CashPeriod, (DateTime, DateTime)>((
      ref,
      range,
    ) async* {
      final business = await ref.watch(currentBusinessProvider.future);
      yield* ref
          .watch(cashRepositoryProvider)
          .watchPeriod(business.id, range.$1, range.$2);
    });

/// Perbaikan stok awal data lama, sekali setelah update ke skema v7
/// (FR-20.6); isinya jumlah bahan yang diperbaiki.
final openingFixProvider = FutureProvider<int>((ref) async {
  final business = await ref.watch(currentBusinessProvider.future);
  return ref.read(stockRepositoryProvider).runOpeningFix(business.id);
});

final archiveRepositoryProvider = Provider(
  (ref) => ArchiveRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(stockRepositoryProvider),
    ref.watch(productRepositoryProvider),
  ),
);

/// Baris satuan tersimpan satu bahan, termasuk yang disembunyikan.
final ingredientUnitsProvider =
    StreamProvider.family<List<IngredientUnit>, String>(
      (ref, id) => ref.watch(stockRepositoryProvider).watchUnits(id),
    );
