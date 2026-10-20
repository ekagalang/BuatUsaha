import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';
import 'db/database_provider.dart';
import 'repositories/business_repository.dart';
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
