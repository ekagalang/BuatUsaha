import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/business_repository.dart';
import 'package:buat_usaha/data/repositories/product_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/domain/costing/pricing.dart';

Decimal d(String value) => Decimal.parse(value);

DateTime oct(int day, [int hour = 9]) => DateTime.utc(2026, 10, day, hour);

void main() {
  late AppDatabase db;
  late StockRepository stock;
  late ProductRepository repo;
  late BusinessRepository business;
  late String businessId;
  late Map<String, String> ids;

  Future<String> ingredient(
    String name,
    BaseUnit unit, {
    String? qty,
    String? cost,
  }) async => (await stock.createIngredient(
    businessId: businessId,
    name: name,
    baseUnit: unit,
    openingQty: qty == null ? null : d(qty),
    openingUnitCost: cost == null ? null : d(cost),
    at: oct(1),
  )).id;

  /// Brownies 1 loyang = 20 pcs. Bahan Rp64.000, gas Rp5.000, upah pemilik
  /// 1,5 jam × Rp15.000, kemasan Rp260/pcs → HPP Rp4.835/pcs.
  ProductInput brownies({
    StockDeductMode? mode,
    List<RecipeInput>? extra,
    int price = 8000,
  }) => ProductInput(
    name: 'Brownies',
    sellingPrice: price,
    yieldQty: d('20'),
    stockDeductMode: mode,
    recipe: [
      RecipeInput(ingredientId: ids['tepung']!, qtyBase: d('250')),
      RecipeInput(ingredientId: ids['cokelat']!, qtyBase: d('200')),
      RecipeInput(ingredientId: ids['telur']!, qtyBase: d('4')),
      RecipeInput(ingredientId: ids['mentega']!, qtyBase: d('200')),
      RecipeInput(ingredientId: ids['gula']!, qtyBase: d('200')),
      ...?extra,
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    stock = StockRepository(db);
    repo = ProductRepository(db, stock);
    business = BusinessRepository(db);
    businessId = (await business.ensureDefault()).id;
    await business.setOwnerHourlyWage(businessId, 15000);
    ids = {
      'tepung': await ingredient('Tepung', BaseUnit.g, qty: '1000', cost: '12'),
      'cokelat': await ingredient(
        'Cokelat',
        BaseUnit.g,
        qty: '300',
        cost: '150',
      ),
      'telur': await ingredient('Telur', BaseUnit.pcs, qty: '10', cost: '2000'),
      'mentega': await ingredient(
        'Mentega',
        BaseUnit.g,
        qty: '1000',
        cost: '100',
      ),
      'gula': await ingredient('Gula', BaseUnit.g, qty: '1000', cost: '15'),
    };
  });
  tearDown(() => db.close());

  Future<ProductView> view(String id) => repo.watchProduct(id).first;

  test('HPP, saran harga, dan kapasitas menu', () async {
    final id = await repo.createProduct(businessId, brownies());
    final menu = await view(id);

    expect(menu.status, HppStatus.complete);
    expect(menu.hpp.materialCostPerBatch, d('64000'));
    expect(menu.hppPerPcs, d('4835'));
    expect(menu.product.hppPerPcs, 4835);
    expect(menu.suggestedByMarkup, 8000);
    expect(menu.marginPct, d('39.56'));
    expect(menu.warning, isNull);
    expect(menu.isReadyStock, isTrue);

    final capacity = menu.capacity!;
    expect(capacity.maxPcs, 30);
    expect(capacity.limitingIngredientIds, [ids['cokelat']]);
    expect(menu.ingredientName(ids['cokelat']!), 'Cokelat');

    final short = menu.shortagesFor(40);
    expect(short.single.ingredientId, ids['cokelat']);
    expect(short.single.missingQty, d('100'));
  });

  test(
    'harga di bawah target margin dan di bawah HPP diberi peringatan',
    () async {
      final id = await repo.createProduct(businessId, brownies(price: 7000));
      expect((await view(id)).warning, PriceWarning.belowTargetMargin);

      await repo.setSellingPrice(id, 4500);
      final menu = await view(id);
      expect(menu.warning, PriceWarning.belowHpp);
      expect(menu.profitPerPcs, d('-335'));
    },
  );

  test('harga bahan berubah → HPP menu ikut diperbarui', () async {
    final id = await repo.createProduct(businessId, brownies());
    await stock.recordPurchase(
      businessId,
      PurchaseInput(
        purchasedAt: oct(10),
        lines: [
          PurchaseLineInput(
            ingredientId: ids['cokelat']!,
            qty: d('300'),
            unitName: 'g',
            factorToBase: Decimal.one,
            totalPrice: 60000,
          ),
        ],
      ),
    );
    // Cokelat rata-rata (45.000 + 60.000) / 600 g = Rp175/g.
    final menu = await view(id);
    expect(menu.hppPerPcs, d('5085'));
    expect(menu.product.hppPerPcs, 5085);
  });

  test('bahan tanpa harga atau upah belum diisi → HPP belum lengkap', () async {
    final vanili = await ingredient('Vanili', BaseUnit.ml);
    final id = await repo.createProduct(
      businessId,
      brownies(
        extra: [RecipeInput(ingredientId: vanili, qtyBase: d('5'))],
      ),
    );
    var menu = await view(id);
    expect(menu.status, HppStatus.incomplete);
    expect(menu.hpp.missingPriceIngredientIds, [vanili]);
    expect(menu.suggestedByMarkup, isNull);
    expect(menu.warning, isNull);

    await stock.setPriceEstimate(vanili, d('100'));
    menu = await view(id);
    expect(menu.status, HppStatus.estimated);
    expect(menu.hppPerPcs, d('4860'));

    await business.setOwnerHourlyWage(businessId, null);
    menu = await view(id);
    expect(menu.status, HppStatus.incomplete);
    expect(menu.costing.wageMissing, isTrue);
    expect(menu.product.hppStatus, HppStatus.incomplete);
  });

  test('ubah resep mengganti bahan dan biaya', () async {
    final id = await repo.createProduct(businessId, brownies());
    final input = await repo.inputOf(id);
    expect(input.recipe, hasLength(5));
    expect(input.costs.map((c) => c.name), ['Gas', 'Upah pemilik', 'Kemasan']);

    await repo.updateProduct(
      id,
      ProductInput(
        name: 'Brownies panggang',
        sellingPrice: 9000,
        yieldQty: d('10'),
        recipe: input.recipe.take(2).toList(),
      ),
    );
    final menu = await view(id);
    expect(menu.product.name, 'Brownies panggang');
    expect(menu.costing.lines, hasLength(2));
    expect(menu.costing.costs, isEmpty);
    // (3.000 + 30.000) / 10.
    expect(menu.hppPerPcs, d('3300'));
  });

  test('produksi ready stock memotong bahan dan menambah stok menu', () async {
    final id = await repo.createProduct(businessId, brownies());
    final productionId = await repo.recordProduction(
      id,
      batchQty: d('1.5'),
      at: oct(15),
    );

    final production = (await repo.watchProductions(id).first).single;
    expect(production.id, productionId);
    expect(production.outputQty, 30);
    expect(production.materialCost, 96000);
    expect(production.otherCost, 49050);
    expect(production.hppPerPcs, 4835);

    expect((await stock.watchIngredient(ids['tepung']!).first).stock, d('625'));
    final menu = await view(id);
    expect(menu.stock, d('30'));
    expect(menu.product.stockUnitCost, 4835);
    expect(menu.stockValue, 145050);
    expect(menu.capacity!.maxPcs, 0);

    await repo.voidProduction(productionId, reason: 'salah catat');
    expect(
      (await stock.watchIngredient(ids['tepung']!).first).stock,
      d('1000'),
    );
    expect((await view(id)).stock, Decimal.zero);
    expect((await repo.watchProductions(id).first).single.voidedAt, isNotNull);
    await expectLater(
      repo.voidProduction(productionId, reason: 'lagi'),
      throwsStateError,
    );
  });

  test('pemakaian bahan aktual menimpa takaran resep', () async {
    final id = await repo.createProduct(businessId, brownies());
    await repo.recordProduction(
      id,
      batchQty: Decimal.one,
      actualUsage: {ids['tepung']!: d('300')},
      at: oct(15),
    );
    expect((await stock.watchIngredient(ids['tepung']!).first).stock, d('700'));
    final production = (await repo.watchProductions(id).first).single;
    // Bahan 64.000 + 50 g tepung × 12.
    expect(production.materialCost, 64600);
  });

  test('produksi ditolak jika stok bahan kurang', () async {
    final id = await repo.createProduct(businessId, brownies());
    await expectLater(
      repo.recordProduction(id, batchQty: d('2'), at: oct(15)),
      throwsA(
        isA<InsufficientStockException>().having(
          (e) => e.ingredientNames,
          'ingredientNames',
          ['Cokelat'],
        ),
      ),
    );
    expect(await repo.watchProductions(id).first, isEmpty);
    expect(
      (await stock.watchIngredient(ids['tepung']!).first).stock,
      d('1000'),
    );
  });

  test('menu pre-order tidak punya stok produk jadi', () async {
    final id = await repo.createProduct(
      businessId,
      brownies(mode: StockDeductMode.onComplete),
    );
    await repo.recordProduction(id, batchQty: Decimal.one, at: oct(15));
    final menu = await view(id);
    expect(menu.isReadyStock, isFalse);
    expect(menu.stock, Decimal.zero);
    expect((await stock.watchIngredient(ids['tepung']!).first).stock, d('750'));
  });

  test('stok awal produk jadi dinilai dengan HPP terkini', () async {
    final id = await repo.createProduct(businessId, brownies());
    await repo.recordProductOpening(id, d('5'));
    await repo.recordProduction(id, batchQty: Decimal.one, at: oct(15));
    final menu = await view(id);
    expect(menu.stock, d('25'));
    expect(menu.product.stockUnitCost, 4835);
  });

  test('daftar menu urut nama dan ikut berubah', () async {
    expect(await repo.watchProducts(businessId).first, isEmpty);
    await repo.createProduct(businessId, brownies());
    await repo.createProduct(
      businessId,
      ProductInput(
        name: 'Bolu',
        sellingPrice: 5000,
        yieldQty: d('8'),
        recipe: [RecipeInput(ingredientId: ids['tepung']!, qtyBase: d('200'))],
      ),
    );
    final names = (await repo.watchProducts(businessId).first).map(
      (p) => p.product.name,
    );
    expect(names, ['Bolu', 'Brownies']);
  });

  test('validasi input menu', () async {
    expect(
      () => repo.createProduct(
        businessId,
        ProductInput(
          name: ' ',
          sellingPrice: 1000,
          yieldQty: Decimal.one,
          recipe: const [],
        ),
      ),
      throwsArgumentError,
    );
    final id = await repo.createProduct(
      businessId,
      ProductInput(
        name: 'Kosong',
        sellingPrice: 1000,
        yieldQty: Decimal.one,
        recipe: const [],
      ),
    );
    expect((await view(id)).status, HppStatus.incomplete);
    await expectLater(
      repo.recordProduction(id, batchQty: Decimal.one),
      throwsStateError,
    );
  });
}
