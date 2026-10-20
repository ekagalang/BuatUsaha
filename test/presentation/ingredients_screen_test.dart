import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/providers.dart';
import 'package:hpp_app/data/repositories/business_repository.dart';
import 'package:hpp_app/data/repositories/stock_repository.dart';
import 'package:hpp_app/presentation/stock/ingredients_screen.dart';
import 'package:hpp_app/presentation/theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('daftar bahan menampilkan nilai modal dan tanda status', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());

    await tester.runAsync(() async {
      final business = await BusinessRepository(db).ensureDefault();
      final repo = StockRepository(db);
      await repo.createIngredient(
        businessId: business.id,
        name: 'Box kemasan',
        baseUnit: BaseUnit.pcs,
        openingQty: Decimal.fromInt(100),
        openingUnitCost: Decimal.fromInt(1500),
      );
      await repo.createIngredient(
        businessId: business.id,
        name: 'Cokelat batang',
        baseUnit: BaseUnit.g,
        minStock: Decimal.fromInt(400),
        openingQty: Decimal.fromInt(300),
        openingUnitCost: Decimal.fromInt(90),
      );
      await repo.createIngredient(
        businessId: business.id,
        name: 'Santan',
        baseUnit: BaseUnit.ml,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const IngredientsScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('Rp177.000'), findsOneWidget);
    expect(
      find.text('Rp150.000 (85%) tertahan di box kemasan'),
      findsOneWidget,
    );
    expect(find.text('Menipis'), findsWidgets);
    expect(find.text('Belum ada harga'), findsWidgets);

    await tester.tap(find.text('Menipis').first);
    await tester.pump();
    expect(find.text('Cokelat batang'), findsOneWidget);
    expect(find.text('Box kemasan'), findsNothing);

    // Drift menjadwalkan timer nol detik saat stream ditutup; habiskan dulu,
    // lalu tutup database di luar waktu palsu test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
