import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/presentation/app.dart';
import 'package:buat_usaha/presentation/layout.dart';
import 'package:buat_usaha/presentation/menu/menu_screen.dart';
import 'package:buat_usaha/presentation/orders/order_detail_screen.dart';
import 'package:buat_usaha/presentation/orders/orders_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/fake_updates.dart';
import '../support/seed.dart';

/// Tampilan tablet (FR-21): 1280×800 mendatar, 800×1280 tegak, HP 360 dp.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Seed s,
    Size size, {
    Widget? home,
    double textScale = 1,
  }) async {
    // MediaQuery membaca ukuran view, bukan surface.
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size;
    addTearDown(tester.view.reset);
    final router = home == null
        ? buildRouter()
        : GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => home)],
          );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(s.db),
          keyValueStoreProvider.overrideWithValue(MemoryStore()),
        ],
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
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester, Seed s) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(s.close);
  }

  Future<void> twoOrders(Seed s) async {
    final now = DateTime.now();
    for (final (name, qty) in [('Bu Sari', 4), ('Arisan RT 05', 6)]) {
      await s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: DateTime(now.year, now.month, now.day, 23, qty * 5),
          customerName: name,
          items: [
            OrderItemInput(productId: s.brownies, qty: qty, unitPrice: 8000),
          ],
        ),
      );
    }
  }

  test('ukuran jendela', () {
    expect(WindowSize.values, hasLength(3));
  });

  testWidgets('HP: navigasi bawah, tablet: rel navigasi', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const Size(360, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await pump(tester, s, const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Pengaturan'), findsWidgets);
    await finish(tester, s);
  });

  testWidgets('mendatar: pesanan pertama terbuka di panel kanan, bisa ganti', (
    tester,
  ) async {
    final s = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(() => twoOrders(s));
    await pump(tester, s, const Size(1280, 800), home: const OrdersScreen());

    // Judul detail di panel kanan + nama di daftar kiri.
    expect(find.text('Bu Sari'), findsNWidgets(2));
    expect(find.text('Arisan RT 05'), findsOneWidget);
    await tester.tap(find.text('Arisan RT 05'));
    await settle(tester);
    expect(find.text('Arisan RT 05'), findsNWidgets(2));
    expect(find.text('Bu Sari'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('HP: daftar pesanan tanpa panel detail', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(() => twoOrders(s));
    await pump(tester, s, const Size(360, 1200), home: const OrdersScreen());
    expect(find.text('Bu Sari'), findsOneWidget);
    expect(find.text('Pilih pesanan untuk melihat detailnya.'), findsNothing);
    await finish(tester, s);
  });

  testWidgets('HP: bar tombol bawah tidak menutupi isi detail', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(() => twoOrders(s));
    final id = (await tester.runAsync(() => s.db.select(s.db.orders).get()))!
        .first
        .id;
    await pump(
      tester,
      s,
      const Size(360, 800),
      home: OrderDetailScreen(id: id),
    );
    expect(find.text('Mulai diproses'), findsOneWidget);
    expect(find.textContaining('ambil sendiri'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('tegak: kartu menu dalam kisi dua kolom (huruf 130%)', (
    tester,
  ) async {
    final s = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => s.products.createProduct(
        s.businessId,
        s.browniesInput(name: 'Cookies'),
      ),
    );
    await pump(
      tester,
      s,
      const Size(720, 1280),
      home: const MenuScreen(),
      textScale: 1.3,
    );
    final brownies = tester.getTopLeft(find.text('Brownies'));
    final cookies = tester.getTopLeft(find.text('Cookies'));
    expect(brownies.dy, cookies.dy);
    expect(brownies.dx, isNot(cookies.dx));
    await finish(tester, s);
  });

  testWidgets('form dibatasi lebar baca di tablet', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const Size(1280, 800));
    final context = tester.element(find.byType(Scaffold).first);
    final padding = readablePadding(
      context,
      const EdgeInsets.fromLTRB(20, 4, 20, 24),
    );
    expect(padding.left, (1280 - readableWidth) / 2);
    await finish(tester, s);
  });
}
