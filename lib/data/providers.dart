import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_notifications.dart';
import '../services/notification_sync.dart';
import 'db/app_database.dart';
import 'db/database_provider.dart';
import 'repositories/business_repository.dart';
import 'repositories/day_close_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/product_repository.dart';
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
