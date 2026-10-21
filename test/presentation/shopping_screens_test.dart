import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/shopping_repository.dart';
import 'package:buat_usaha/presentation/menu/menu_form_screen.dart';
import 'package:buat_usaha/presentation/stock/purchase_form_screen.dart';
import 'package:buat_usaha/presentation/stock/shopping_list_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';

import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 40 brownies besok (cokelat kurang 100 g) dan mentega di bawah minimum.
Future<Seed> _seed() async {
  final s = await Seed.create();
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  await s.orders.createOrder(
    s.businessId,
    OrderInput(
      dueAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13),
      items: [OrderItemInput(productId: s.brownies, qty: 40, unitPrice: 8000)],
    ),
  );
  await s.stock.updateIngredient(s.ids['mentega']!, minStock: d('1200'));
  return s;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> pumpApp(
    WidgetTester tester,
    Seed s, {
    double textScale = 1,
    Widget? home,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => home ?? const ShoppingListScreen(),
        ),
        GoRoute(
          path: '/bahan/belanja',
          builder: (_, state) => PurchaseFormScreen(
            fromShoppingList: state.uri.queryParameters['daftar'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(s.db)],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> finish(WidgetTester tester, Seed s) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(s.close);
  }

  testWidgets('daftar dihitung otomatis: alasan, perkiraan, centang', (
    tester,
  ) async {
    final s = (await tester.runAsync(_seed))!;
    await pumpApp(tester, s);

    expect(find.text('Perlu dibeli (2)'), findsOneWidget);
    expect(find.text('Cokelat'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('Untuk pesanan'), findsOneWidget);
    expect(find.text('Mentega'), findsOneWidget);
    expect(find.text('Di bawah minimum'), findsOneWidget);
    expect(find.text('±Rp15.000'), findsOneWidget);
    expect(
      find.textContaining('2 bahan · untuk 1 pesanan s.d.'),
      findsOneWidget,
    );
    expect(find.text('Centang yang sudah dibeli'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Tandai Cokelat sudah dibeli'));
    await _settle(tester);
    expect(find.text('Sudah dibeli (1)'), findsOneWidget);
    expect(find.text('Dicentang'), findsOneWidget);
    expect(find.text('Catat jadi belanja (1)'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('tambah barang lain dan ganti rentang', (tester) async {
    final s = (await tester.runAsync(_seed))!;
    await pumpApp(tester, s);

    await tester.tap(find.text('Tambah barang'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Plastik kemasan');
    await _settle(tester);
    await tester.tap(find.text('+ Barang lain: "Plastik kemasan"'));
    await _settle(tester);
    expect(find.text('Plastik kemasan'), findsOneWidget);
    expect(find.text('Barang lain'), findsOneWidget);
    expect(find.textContaining('+ 1 barang lain'), findsOneWidget);

    await tester.tap(find.text('7 hari'));
    await _settle(tester);
    // Barang tambahan sendiri tetap ada setelah hitung ulang.
    expect(find.text('Plastik kemasan'), findsOneWidget);
    expect(find.text('Perlu dibeli (3)'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('ubah jumlah item lewat lembar ubah', (tester) async {
    final s = (await tester.runAsync(_seed))!;
    await pumpApp(tester, s);

    await tester.tap(find.text('Cokelat'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Tambah'));
    await _settle(tester);
    expect(find.text('perkiraan Rp15.150'), findsOneWidget);
    await tester.tap(find.text('Simpan'));
    await _settle(tester);
    expect(find.text('101 g'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('catat jadi belanja: form terisi lalu item Tercatat', (
    tester,
  ) async {
    final s = (await tester.runAsync(_seed))!;
    await pumpApp(tester, s);
    await tester.tap(find.bySemanticsLabel('Tandai Cokelat sudah dibeli'));
    await _settle(tester);
    await tester.tap(find.text('Catat jadi belanja (1)'));
    await _settle(tester);

    expect(find.textContaining('Dari daftar belanja: 1 bahan'), findsOneWidget);
    expect(
      find.text('Harga perkiraan dari harga rata-rata; ganti sesuai struk.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Simpan belanja'));
    await _settle(tester);

    expect(find.text('Tercatat'), findsOneWidget);
    final cokelat = await tester.runAsync(
      () => s.stock.watchIngredient(s.ids['cokelat']!).first,
    );
    expect(cokelat!.stock, d('400'));
    await finish(tester, s);
  });

  testWidgets('daftar belanja tidak terpotong dengan huruf 130%', (
    tester,
  ) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    final s = (await tester.runAsync(_seed))!;
    await tester.runAsync(() async {
      final repo = ShoppingRepository(s.db, s.orders);
      final list = await repo.activeList(s.businessId);
      await repo.recalculate(list.id);
      await repo.addOther(list.id, 'Plastik kemasan ukuran besar', qty: 2);
      await repo.setChecked(
        (await repo.view(list.id)).lines.first.item.id,
        checked: true,
      );
    });
    await pumpApp(tester, s, textScale: 1.3);
    expect(find.text('Sudah dibeli (1)'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('form menu ready stock: kolom stok jaga', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pumpApp(tester, s, home: MenuFormScreen(id: s.brownies));
    expect(find.text('Stok jaga (opsional)'), findsOneWidget);
    await finish(tester, s);
  });

  test('teks bagikan dan label jumlah', () async {
    final s = await Seed.create();
    addTearDown(s.close);
    await s.stock.addCustomUnit(
      s.ids['cokelat']!,
      unitName: 'pack',
      factorToBase: d('200'),
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await s.orders.createOrder(
      s.businessId,
      OrderInput(
        dueAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13),
        items: [
          OrderItemInput(productId: s.brownies, qty: 40, unitPrice: 8000),
        ],
      ),
    );
    final repo = ShoppingRepository(s.db, s.orders);
    final list = await repo.activeList(s.businessId);
    await repo.recalculate(list.id);
    await repo.addOther(list.id, 'Plastik kemasan', qty: 2, unitName: 'pak');
    final view = await repo.view(list.id);

    expect(shoppingQtyLabel(view.lines.first), '1 pack × 200 g = 200 g');
    expect(shoppingQtyLabel(view.lines.last), '2 pak');
    final text = shoppingShareText(view, 'Dapur Bu Rina');
    expect(
      text,
      startsWith('*Daftar belanja · Dapur Bu Rina*\nUntuk pesanan s.d. '),
    );
    expect(text, contains('☐ Cokelat — 1 pack × 200 g = 200 g (±Rp30.000)'));
    expect(text, contains('☐ Plastik kemasan — 2 pak'));
    expect(text, contains('Perkiraan total: ±Rp30.000'));
  });
}
