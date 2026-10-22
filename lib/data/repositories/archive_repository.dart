import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'hpp_refresher.dart';
import 'product_repository.dart';
import 'stock_repository.dart';

/// Arsipkan: disembunyikan dan bisa dipulihkan. Hapus: tanpa riwayat
/// dihapus permanen; dengan riwayat tidak tampil lagi di mana pun, tetapi
/// barisnya tetap supaya laporan lama tidak berubah (FR-20.2, FR-20.4).
enum RemoveAction { archive, delete }

/// Apa saja yang terkait dengan satu bahan sebelum diarsipkan/dihapus.
class IngredientUsage {
  const IngredientUsage({
    required this.hasHistory,
    required this.menus,
    required this.stock,
    required this.value,
  });

  /// Ada belanja, pemakaian, opname, penyesuaian, atau bahan rusak.
  final bool hasHistory;

  /// Menu (belum dihapus) yang resepnya memakai bahan ini.
  final List<Product> menus;
  final Decimal stock;
  final int value;
}

class ProductUsage {
  const ProductUsage({
    required this.hasHistory,
    required this.soldCount,
    required this.openOrders,
    required this.stock,
  });

  /// Pernah dipesan, dijual, atau diproduksi.
  final bool hasHistory;
  final int soldCount;

  /// Nomor pesanan belum selesai yang memuat menu ini.
  final List<String> openOrders;

  /// Stok menu jadi.
  final Decimal stock;
}

/// Ubah status bahan dan menu: arsipkan, pulihkan, hapus. Tidak ada keadaan
/// "tidak bisa"; setiap akibat jadi pilihan (prinsip fleksibel, PRD 22 Okt).
class ArchiveRepository {
  ArchiveRepository(this._db, this._stock, this._products);

  final AppDatabase _db;
  final StockRepository _stock;
  final ProductRepository _products;

  DateTime _now() => DateTime.now().toUtc();

  // ---------------------------------------------------------------- Bahan

  Future<IngredientUsage> ingredientUsage(String ingredientId) async {
    final ingredient = await (_db.select(
      _db.ingredients,
    )..where((t) => t.id.equals(ingredientId))).getSingle();
    final history =
        await (_db.select(_db.stockMovements)
              ..where(
                (t) =>
                    t.ingredientId.equals(ingredientId) &
                    t.type.equalsValue(MovementType.opening).not(),
              )
              ..limit(1))
            .getSingleOrNull();
    final menus =
        await (_db.select(_db.products).join([
                innerJoin(
                  _db.recipeItems,
                  _db.recipeItems.productId.equalsExp(_db.products.id),
                ),
              ])
              ..where(
                _db.recipeItems.ingredientId.equals(ingredientId) &
                    _db.products.deletedAt.isNull(),
              )
              ..orderBy([OrderingTerm.asc(_db.products.name)]))
            .map((r) => r.readTable(_db.products))
            .get();
    final view = IngredientView(ingredient);
    return IngredientUsage(
      hasHistory: history != null,
      menus: menus,
      stock: view.stock,
      value: view.value,
    );
  }

  /// [wasteRemaining]: sisa stok dicatat sebagai bahan rusak (masuk rugi).
  /// [removeFromRecipes]: bahan dikeluarkan dari resep menu yang memakainya
  /// dan HPP-nya dihitung ulang; kalau tidak, menu tetap memakai harga
  /// terakhir bahan ini.
  Future<void> removeIngredient(
    String ingredientId, {
    required RemoveAction action,
    bool wasteRemaining = false,
    bool removeFromRecipes = false,
  }) {
    return _db.transaction(() async {
      var usage = await ingredientUsage(ingredientId);
      if (wasteRemaining && usage.stock > Decimal.zero) {
        await _stock.recordWaste(
          ingredientId,
          qtyBase: usage.stock,
          note: action == RemoveAction.archive
              ? 'Sisa saat diarsipkan'
              : 'Sisa saat dihapus',
        );
      }
      if (removeFromRecipes && usage.menus.isNotEmpty) {
        await (_db.delete(
          _db.recipeItems,
        )..where((t) => t.ingredientId.equals(ingredientId))).go();
        for (final p in usage.menus) {
          await refreshProductHpp(_db, p.id, cause: HppChangeCause.recipe);
        }
      }
      usage = await ingredientUsage(ingredientId);
      final stillInRecipe =
          await (_db.select(_db.recipeItems)
                ..where((t) => t.ingredientId.equals(ingredientId))
                ..limit(1))
              .getSingleOrNull();
      if (action == RemoveAction.delete &&
          !usage.hasHistory &&
          stillInRecipe == null) {
        await (_db.delete(
          _db.shoppingListItems,
        )..where((t) => t.ingredientId.equals(ingredientId))).go();
        await (_db.delete(
          _db.stockMovements,
        )..where((t) => t.ingredientId.equals(ingredientId))).go();
        await (_db.delete(
          _db.ingredientUnits,
        )..where((t) => t.ingredientId.equals(ingredientId))).go();
        await (_db.delete(
          _db.ingredients,
        )..where((t) => t.id.equals(ingredientId))).go();
        return;
      }
      await (_db.update(
        _db.ingredients,
      )..where((t) => t.id.equals(ingredientId))).write(
        IngredientsCompanion(
          archivedAt: Value(_now()),
          deletedAt: action == RemoveAction.delete
              ? Value(_now())
              : const Value.absent(),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  Future<void> restoreIngredient(String ingredientId) =>
      (_db.update(
        _db.ingredients,
      )..where((t) => t.id.equals(ingredientId))).write(
        IngredientsCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(_now()),
        ),
      );

  // ----------------------------------------------------------------- Menu

  Future<ProductUsage> productUsage(String productId) async {
    final product = await (_db.select(
      _db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    final lines = await (_db.select(_db.orderItems).join([
      innerJoin(_db.orders, _db.orders.id.equalsExp(_db.orderItems.orderId)),
    ])..where(_db.orderItems.productId.equals(productId))).get();
    final orders = [for (final r in lines) r.readTable(_db.orders)];
    final production =
        await (_db.select(_db.productions)
              ..where((t) => t.productId.equals(productId))
              ..limit(1))
            .getSingleOrNull();
    final movement =
        await (_db.select(_db.productStockMovements)
              ..where(
                (t) =>
                    t.productId.equals(productId) &
                    t.type.equalsValue(ProductMovementType.opening).not(),
              )
              ..limit(1))
            .getSingleOrNull();
    final open = {
      for (final o in orders)
        if (o.status != OrderStatus.completed &&
            o.status != OrderStatus.cancelled)
          o.orderNo,
    }.toList()..sort();
    return ProductUsage(
      hasHistory: orders.isNotEmpty || production != null || movement != null,
      soldCount: {
        for (final o in orders)
          if (o.status == OrderStatus.completed && o.voidedAt == null) o.id,
      }.length,
      openOrders: open,
      stock: dec(product.currentStock),
    );
  }

  /// [wasteRemaining]: sisa stok menu jadi dicatat dibuang (masuk rugi
  /// produk). Pesanan yang belum selesai tetap berjalan.
  Future<void> removeProduct(
    String productId, {
    required RemoveAction action,
    bool wasteRemaining = false,
  }) {
    return _db.transaction(() async {
      final usage = await productUsage(productId);
      if (wasteRemaining && usage.stock > Decimal.zero) {
        await _products.issueProduct(
          productId,
          type: ProductMovementType.waste,
          qty: usage.stock,
          reason: WasteReason.other,
          note: action == RemoveAction.archive
              ? 'Sisa saat diarsipkan'
              : 'Sisa saat dihapus',
        );
      }
      final again = await productUsage(productId);
      if (action == RemoveAction.delete && !again.hasHistory) {
        await (_db.delete(
          _db.productStockMovements,
        )..where((t) => t.productId.equals(productId))).go();
        // Resep, biaya lain, harga channel, dan riwayat HPP ikut terhapus
        // (cascade).
        await (_db.delete(
          _db.products,
        )..where((t) => t.id.equals(productId))).go();
        return;
      }
      await (_db.update(
        _db.products,
      )..where((t) => t.id.equals(productId))).write(
        ProductsCompanion(
          archivedAt: Value(_now()),
          deletedAt: action == RemoveAction.delete
              ? Value(_now())
              : const Value.absent(),
          updatedAt: Value(_now()),
        ),
      );
    });
  }

  Future<void> restoreProduct(String productId) =>
      (_db.update(_db.products)..where((t) => t.id.equals(productId))).write(
        ProductsCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(_now()),
        ),
      );
}
