import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/repositories/business_repository.dart';
import 'package:hpp_app/data/repositories/order_repository.dart';
import 'package:hpp_app/data/repositories/product_repository.dart';
import 'package:hpp_app/data/repositories/stock_repository.dart';

Decimal d(String value) => Decimal.parse(value);

/// Data contoh PRD: brownies 1 resep = 20 pcs. Bahan Rp64.000, gas Rp5.000,
/// upah pemilik 1,5 jam × Rp15.000, kemasan Rp260/pcs → HPP Rp4.835/pcs;
/// cokelat cukup 1,5 resep (30 pcs).
class Seed {
  Seed._(this.db)
    : business = BusinessRepository(db),
      stock = StockRepository(db) {
    products = ProductRepository(db, stock);
    orders = OrderRepository(db, stock, products);
  }

  final AppDatabase db;
  final BusinessRepository business;
  final StockRepository stock;
  late final ProductRepository products;
  late final OrderRepository orders;
  late final String businessId;
  final ids = <String, String>{};
  late final String brownies;

  static Future<Seed> create({AppDatabase? db, DateTime? openingAt}) async {
    final seed = Seed._(db ?? AppDatabase(NativeDatabase.memory()));
    await seed._init(openingAt ?? DateTime.utc(2026, 10, 1));
    return seed;
  }

  Future<void> _init(DateTime at) async {
    businessId = (await business.ensureDefault()).id;
    await business.setOwnerHourlyWage(businessId, 15000);
    Future<String> ingredient(
      String name,
      BaseUnit unit,
      String qty,
      String cost,
    ) async => (await stock.createIngredient(
      businessId: businessId,
      name: name,
      baseUnit: unit,
      openingQty: d(qty),
      openingUnitCost: d(cost),
      at: at,
    )).id;
    ids['tepung'] = await ingredient('Tepung', BaseUnit.g, '1000', '12');
    ids['cokelat'] = await ingredient('Cokelat', BaseUnit.g, '300', '150');
    ids['telur'] = await ingredient('Telur', BaseUnit.pcs, '10', '2000');
    ids['mentega'] = await ingredient('Mentega', BaseUnit.g, '1000', '100');
    ids['gula'] = await ingredient('Gula', BaseUnit.g, '1000', '15');
    brownies = await products.createProduct(businessId, browniesInput());
  }

  ProductInput browniesInput({
    StockDeductMode? mode,
    String name = 'Brownies',
  }) => ProductInput(
    name: name,
    sellingPrice: 8000,
    yieldQty: d('20'),
    shelfLifeDays: 3,
    stockDeductMode: mode,
    recipe: [
      RecipeInput(ingredientId: ids['tepung']!, qtyBase: d('250')),
      RecipeInput(ingredientId: ids['cokelat']!, qtyBase: d('200')),
      RecipeInput(ingredientId: ids['telur']!, qtyBase: d('4')),
      RecipeInput(ingredientId: ids['mentega']!, qtyBase: d('200')),
      RecipeInput(ingredientId: ids['gula']!, qtyBase: d('200')),
    ],
    costs: [
      const CostInput(
        name: 'Gas',
        costType: CostType.utilities,
        basis: CostBasis.perBatch,
        amount: 5000,
      ),
      CostInput(
        name: 'Upah pemilik',
        costType: CostType.labor,
        basis: CostBasis.perBatch,
        laborHours: d('1.5'),
      ),
      const CostInput(
        name: 'Kemasan',
        costType: CostType.other,
        basis: CostBasis.perPcs,
        amount: 260,
      ),
    ],
  );

  Future<Decimal> ingredientStock(String key) async =>
      (await stock.watchIngredient(ids[key]!).first).stock;

  Future<ProductView> product(String id) => products.watchProduct(id).first;

  Future<String> channel(String name, String pct) async {
    await orders.saveChannel(businessId, name: name, commissionPct: d(pct));
    return (await orders.watchChannels(businessId).first)
        .firstWhere((c) => c.name == name)
        .id;
  }

  Future<void> close() => db.close();
}
