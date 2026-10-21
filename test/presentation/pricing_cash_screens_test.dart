import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/pricing_repository.dart';
import 'package:buat_usaha/presentation/cash/cash_accounts_screen.dart';
import 'package:buat_usaha/presentation/cash/cash_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_detail_screen.dart';
import 'package:buat_usaha/presentation/menu/price_simulation_screen.dart';
import 'package:buat_usaha/presentation/orders/order_form_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';

import '../support/seed.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Seed s,
    Widget home, {
    double textScale = 1,
    double height = 2400,
  }) async {
    await tester.binding.setSurfaceSize(Size(360, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => home)],
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
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester, Seed s) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(s.close);
  }

  testWidgets('detail menu: harga GoFood pakai saran', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => s.orders.saveChannel(
        s.businessId,
        name: 'Mitra 20%',
        commissionPct: d('20'),
      ),
    );
    await pump(tester, s, MenuDetailScreen(id: s.brownies), height: 4200);

    await tester.tap(find.text('Mitra 20%'));
    await settle(tester);
    expect(find.text('Harga di Mitra 20%'), findsOneWidget);
    await tester.tap(find.text('Pakai saran'));
    await settle(tester);
    await tester.tap(find.text('Simpan'));
    await settle(tester);

    final prices = (await tester.runAsync(
      () => PricingRepository(
        s.db,
        s.products,
      ).watchChannelPrices(s.businessId).first,
    ))!;
    expect(prices[s.brownies]!.values, [10000]);
    expect(find.text('Rp10.000'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('form pesanan: ganti channel ikut harga channel', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    final mitra = (await tester.runAsync(() => s.channel('Mitra 20%', '20')))!;
    await tester.runAsync(
      () => PricingRepository(
        s.db,
        s.products,
      ).setChannelPrice(s.brownies, mitra, price: 10000),
    );
    await pump(tester, s, const OrderFormScreen(direct: true));

    await tester.tap(find.text('Tambah item'));
    await settle(tester);
    await tester.tap(find.text('Brownies'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '8.000'), findsOneWidget);

    await tester.tap(find.text('Mitra 20% · 20%'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '10.000'), findsOneWidget);

    await tester.tap(find.text('Langsung'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '8.000'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('simulasi: cokelat naik 50%', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const PriceSimulationScreen());

    await tester.tap(find.text('Tambah bahan'));
    await settle(tester);
    await tester.tap(find.text('Cokelat'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '50');
    await settle(tester);

    expect(find.text('Menu terdampak (1)'), findsOneWidget);
    expect(find.text('HPP Rp4.835 → Rp5.585 (+Rp750)'), findsOneWidget);
    expect(
      find.text('Saran harga Rp9.500 supaya margin tetap'),
      findsOneWidget,
    );
    await finish(tester, s);
  });

  testWidgets('kas: catat modal masuk, saldo bertambah (huruf 130%)', (
    tester,
  ) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const CashScreen(), textScale: 1.3);
    expect(find.text('Saldo kas hari ini'), findsOneWidget);
    expect(find.text('QRIS/e-wallet'), findsOneWidget);
    expect(find.text('Kenapa laba beda dengan kas?'), findsOneWidget);

    await tester.tap(find.text('Catat kas'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nominal'), '100000');
    await tester.tap(find.text('Simpan'));
    await settle(tester);

    expect(find.text('Modal masuk'), findsOneWidget);
    expect(find.text('+Rp100.000'), findsOneWidget);
    expect(find.text('Rp100.000'), findsWidgets);
    await finish(tester, s);
  });

  testWidgets('akun kas: daftar dan cara bayar', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const CashAccountsScreen());
    expect(
      find.text('Tunai · saldo awal Rp0 · menerima Tunai, Lainnya'),
      findsOneWidget,
    );
    await tester.tap(find.text('Bank'));
    await settle(tester);
    expect(find.text('Ubah akun'), findsOneWidget);
    expect(find.text('Pembayaran yang masuk ke akun ini'), findsOneWidget);
    await finish(tester, s);
  });
}
