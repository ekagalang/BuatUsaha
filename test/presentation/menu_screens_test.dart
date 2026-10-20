import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/business_repository.dart';
import 'package:buat_usaha/data/repositories/product_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/presentation/menu/menu_detail_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_form_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';

Decimal d(String value) => Decimal.parse(value);

/// Brownies 20 pcs: bahan Rp64.000 + gas Rp5.000 + upah 1,5 jam × Rp15.000
/// + kemasan Rp260/pcs → HPP Rp4.835; cokelat cukup 1,5 resep. Bolu memakai
/// santan yang belum ada harganya.
Future<String> _seed(AppDatabase db) async {
  final business = BusinessRepository(db);
  final businessId = (await business.ensureDefault()).id;
  await business.setOwnerHourlyWage(businessId, 15000);
  final stock = StockRepository(db);
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
  )).id;
  final tepung = await ingredient('Tepung', BaseUnit.g, '1000', '12');
  final cokelat = await ingredient('Cokelat', BaseUnit.g, '300', '150');
  final telur = await ingredient('Telur', BaseUnit.pcs, '10', '2000');
  final mentega = await ingredient('Mentega', BaseUnit.g, '1000', '100');
  final gula = await ingredient('Gula', BaseUnit.g, '1000', '15');
  final santan = (await stock.createIngredient(
    businessId: businessId,
    name: 'Santan',
    baseUnit: BaseUnit.ml,
  )).id;
  final products = ProductRepository(db, stock);
  final id = await products.createProduct(
    businessId,
    ProductInput(
      name: 'Brownies',
      sellingPrice: 8000,
      yieldQty: d('20'),
      shelfLifeDays: 3,
      recipe: [
        RecipeInput(ingredientId: tepung, qtyBase: d('250')),
        RecipeInput(ingredientId: cokelat, qtyBase: d('200')),
        RecipeInput(ingredientId: telur, qtyBase: d('4')),
        RecipeInput(ingredientId: mentega, qtyBase: d('200')),
        RecipeInput(ingredientId: gula, qtyBase: d('200')),
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
    ),
  );
  await products.createProduct(
    businessId,
    ProductInput(
      name: 'Bolu pandan',
      sellingPrice: 35000,
      yieldQty: d('1'),
      stockDeductMode: StockDeductMode.onComplete,
      recipe: [
        RecipeInput(ingredientId: tepung, qtyBase: d('200')),
        RecipeInput(ingredientId: santan, qtyBase: d('200')),
      ],
    ),
  );
  return id;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db,
  Widget screen,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: buildAppTheme(), home: screen),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

/// Drift menjadwalkan timer nol detik saat stream ditutup; habiskan dulu,
/// lalu tutup database di luar waktu palsu test.
Future<void> _close(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('daftar menu: HPP, margin, kapasitas, dan tanda', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() => _seed(db));
    await _pumpScreen(tester, db, const MenuScreen());

    expect(find.text('Brownies'), findsOneWidget);
    expect(find.text('Rp4.835'), findsOneWidget);
    expect(find.text('39,6%'), findsOneWidget);
    expect(find.text('Bisa jadi 30 pcs · pembatas: cokelat'), findsOneWidget);
    expect(find.text('Ready stock · stok 0 pcs'), findsOneWidget);
    expect(find.text('Pre-order · tanpa stok'), findsOneWidget);
    expect(find.text('HPP belum lengkap'), findsOneWidget);

    await tester.tap(find.text('Perlu perhatian'));
    await tester.pump();
    expect(find.text('Bolu pandan'), findsOneWidget);
    expect(find.text('Brownies'), findsNothing);

    await _close(tester, db);
  });

  testWidgets('detail menu: HPP, saran harga, rincian, kapasitas', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = (await tester.runAsync(() => _seed(db)))!;
    await tester.binding.setSurfaceSize(const Size(360, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, db, MenuDetailScreen(id: id));

    expect(
      find.text('Ready stock · 1 resep = 20 pcs · umur simpan 3 hari'),
      findsOneWidget,
    );
    expect(find.text('Lengkap'), findsOneWidget);
    expect(find.text('Rp3.165'), findsOneWidget);
    expect(find.text('Saran harga jual'), findsOneWidget);
    expect(find.text('Sudah dipakai'), findsOneWidget);
    expect(find.text('Rp64.000'), findsOneWidget);
    expect(find.text('Rp91.500'), findsOneWidget);
    expect(find.text('Rp22.500'), findsOneWidget);
    expect(find.text('Bisa jadi 30 pcs'), findsOneWidget);
    expect(find.text('Cokelat (pembatas)'), findsOneWidget);
    expect(find.text('Belum ada produksi.'), findsOneWidget);
    expect(find.text('Catat produksi'), findsOneWidget);

    // Target 40 pcs: cokelat kurang 100 g × Rp150.
    expect(find.text('Rp15.000'), findsWidgets);

    await tester.tap(find.text('Margin 40%'));
    await tester.pump();
    // 4.835 / 0,6 = 8.058,33 → Rp8.500.
    expect(find.text('Rp8.500'), findsOneWidget);
    expect(find.text('Pakai harga ini'), findsOneWidget);

    await _close(tester, db);
  });

  testWidgets('ubah resep memuat isian dan menghitung HPP langsung', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = (await tester.runAsync(() => _seed(db)))!;
    await tester.binding.setSurfaceSize(const Size(360, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpScreen(tester, db, MenuFormScreen(id: id));

    expect(find.text('Ubah resep'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Brownies'), findsOneWidget);
    expect(find.text('Rp4.835'), findsOneWidget);
    expect(find.text('Lengkap'), findsOneWidget);
    expect(find.text('Saran Rp8.000 (markup 60%)'), findsOneWidget);

    // Upah 2 jam: (64.000 + 5.000 + 30.000) / 20 + 260 = 5.210.
    await tester.enterText(find.widgetWithText(TextField, '1,5'), '2');
    await tester.pump();
    expect(find.text('Rp5.210'), findsOneWidget);

    await _close(tester, db);
  });
}
