import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/providers.dart';
import 'package:hpp_app/data/repositories/day_close_repository.dart';
import 'package:hpp_app/data/repositories/expense_repository.dart';
import 'package:hpp_app/data/repositories/order_repository.dart';
import 'package:hpp_app/presentation/home/home_screen.dart';
import 'package:hpp_app/presentation/reports/day_close_screen.dart';
import 'package:hpp_app/presentation/reports/reports_screen.dart';
import 'package:hpp_app/presentation/settings/settings_screen.dart';
import 'package:hpp_app/presentation/theme.dart';

import '../support/seed.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(360, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: buildAppTheme(), home: screen),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
}

/// Hari ini: 30 brownies dibuat, 25 terjual; ojek Rp20.000.
Future<Seed> _seedDay(WidgetTester tester, {bool close = true}) async {
  final seed = await tester.runAsync(() async {
    final s = await Seed.create();
    final now = DateTime.now();
    await s.products.recordProduction(s.brownies, batchQty: d('1.5'), at: now);
    await s.orders.recordDirectSale(
      s.businessId,
      OrderInput(
        dueAt: now,
        items: [
          OrderItemInput(productId: s.brownies, qty: 25, unitPrice: 8000),
        ],
      ),
    );
    if (close) {
      await DayCloseRepository(s.db, s.products).closeDay(s.businessId, now, [
        DiscardInput(productId: s.brownies, qty: d('5')),
      ]);
    }
    final expenses = ExpenseRepository(s.db);
    final transport = (await expenses.watchCategories(s.businessId).first)
        .firstWhere((c) => c.name == 'Transport');
    await expenses.addExpense(
      s.businessId,
      categoryId: transport.id,
      amount: 20000,
      spentAt: now,
      note: 'ojek',
    );
    return s;
  });
  return seed!;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('laporan harian: status, rincian, dan per menu', (tester) async {
    final s = await _seedDay(tester);
    await _pump(tester, s.db, const ReportsScreen());

    // 200.000 − 120.875 − 24.175 − 20.000.
    expect(find.text('Rp34.950'), findsWidgets);
    expect(find.text('Untung'), findsOneWidget);
    expect(find.text('Rp54.950'), findsWidgets);
    expect(find.text('Pengeluaran hari ini (ojek)'), findsOneWidget);
    expect(find.text('5 dibuang'), findsOneWidget);
    expect(find.text('Tutup hari sudah dicatat'), findsOneWidget);

    await tester.tap(find.text('Bulan'));
    await _settle(tester);
    expect(find.text('Laba bersih periode'), findsOneWidget);
    expect(find.text('Menu terlaris'), findsOneWidget);

    await _close(tester, s.db);
  });

  testWidgets('Tutup hari: sisa dibuang dihitung rugi lalu disimpan', (
    tester,
  ) async {
    final s = await _seedDay(tester, close: false);
    await _pump(tester, s.db, const DayCloseScreen());

    expect(find.text('Brownies'), findsOneWidget);
    expect(find.text('Sisa 5 pcs · HPP Rp4.835'), findsOneWidget);
    await tester.tap(find.byTooltip('Tambah yang dibuang'));
    await tester.tap(find.byTooltip('Tambah yang dibuang'));
    await tester.pump();
    expect(find.text('Rugi: Rp9.670'), findsOneWidget);
    expect(find.text('Disimpan: 3'), findsOneWidget);

    await tester.tap(find.text('Simpan Tutup hari'));
    await _settle(tester);
    final stock = await tester.runAsync(() => s.product(s.brownies));
    expect(stock!.stock, d('3'));

    await _close(tester, s.db);
  });

  testWidgets('Beranda menampilkan status hari ini dan catat cepat', (
    tester,
  ) async {
    final s = await _seedDay(tester);
    await _pump(tester, s.db, const HomeScreen());

    expect(find.text('Hari ini, setelah Tutup hari'), findsOneWidget);
    expect(find.text('Rp34.950'), findsWidgets);
    expect(find.text('Catat cepat'), findsOneWidget);
    expect(find.text('Tutup hari'), findsOneWidget);
    expect(find.text('Modal bahan'), findsOneWidget);

    await _close(tester, s.db);
  });

  testWidgets('Pengaturan menampilkan semua bagian dan channel bawaan', (
    tester,
  ) async {
    final s = await tester.runAsync(Seed.create);
    await _pump(tester, s!.db, const SettingsScreen());

    expect(find.text('Profil usaha'), findsOneWidget);
    expect(find.text('Harga dan HPP'), findsOneWidget);
    expect(find.text('Notifikasi'), findsOneWidget);
    expect(find.text('GoFood'), findsOneWidget);
    expect(find.text('Backup: bagikan file data'), findsOneWidget);

    await tester.tap(find.text('Izinkan stok minus'));
    await _settle(tester);
    final business = await tester.runAsync(
      () => s.business.watch(s.businessId).first,
    );
    expect(business!.allowNegativeStock, isTrue);

    await _close(tester, s.db);
  });
}
