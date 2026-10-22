import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/presentation/menu/menu_form_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_screen.dart';
import 'package:buat_usaha/presentation/settings/settings_screen.dart';
import 'package:buat_usaha/presentation/stock/ingredient_detail_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/screen.dart';
import '../support/fake_updates.dart';
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
    MemoryStore? store,
    double textScale = 1,
  }) async {
    setScreenSize(tester, const Size(360, 2400));
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => home)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(s.db),
          keyValueStoreProvider.overrideWithValue(store ?? MemoryStore()),
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
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(s.close);
  }

  testWidgets('detail bahan baru: isi stok awal dan ubah bahan (130%)', (
    tester,
  ) async {
    final s = (await tester.runAsync(Seed.create))!;
    final roti = (await tester.runAsync(
      () => s.stock.createIngredient(
        businessId: s.businessId,
        name: 'Roti burger',
        baseUnit: BaseUnit.pcs,
        estimatedUnitCost: d('1250'),
      ),
    ))!;
    await pump(tester, s, IngredientDetailScreen(id: roti.id), textScale: 1.3);
    expect(find.text('Belum ada stok'), findsOneWidget);
    expect(find.text('Isi stok awal'), findsOneWidget);
    expect(find.text('Satuan'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu lainnya'));
    await settle(tester);
    expect(find.text('Arsipkan bahan'), findsOneWidget);
    await tester.tap(find.text('Ubah bahan'));
    await settle(tester);
    expect(find.text('Dihitung dalam'), findsOneWidget);
    await tester.tap(find.text('butir'));
    await settle(tester);
    await tester.tap(find.text('Simpan'));
    await settle(tester);
    final saved = (await tester.runAsync(
      () => s.stock.watchIngredient(roti.id).first,
    ))!;
    expect(saved.ingredient.countUnit, 'butir');
    await finish(tester, s);
  });

  testWidgets('hapus bahan di resep: pilihan, bukan larangan', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, IngredientDetailScreen(id: s.ids['telur']!));
    await tester.tap(find.byTooltip('Menu lainnya'));
    await settle(tester);
    await tester.tap(find.text('Hapus bahan'));
    await settle(tester);
    expect(find.text('Telur sudah punya riwayat'), findsNothing);
    expect(find.textContaining('Dipakai di resep Brownies'), findsOneWidget);
    expect(
      find.text('Hapus juga dari resep (HPP dihitung ulang)'),
      findsOneWidget,
    );
    expect(
      find.text('Catat sisa sebagai rusak (masuk rugi bahan)'),
      findsOneWidget,
    );
    await finish(tester, s);
  });

  testWidgets('form menu baru menyimpan draf otomatis', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    final store = MemoryStore();
    await pump(tester, s, const MenuFormScreen(), store: store);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nama menu'),
      'Burger keju',
    );
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(store.values['menu.drafts'], contains('Burger keju'));
    await finish(tester, s);
  });

  testWidgets('layar Menu menampilkan draf', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    final store = MemoryStore()
      ..values['menu.drafts'] =
          '[{"id":"baru-1","productId":null,'
          '"savedAt":"2026-10-22T10:15:00.000",'
          '"data":{"name":"Burger keju","recipe":[]}}]';
    await pump(tester, s, const MenuScreen(), store: store);
    expect(find.text('Draf (1)'), findsOneWidget);
    expect(find.text('Burger keju'), findsOneWidget);
    expect(find.text('Lanjutkan'), findsOneWidget);
    await finish(tester, s);
  });

  testWidgets('pengaturan channel: potongan Rupiah per pcs', (tester) async {
    final s = (await tester.runAsync(Seed.create))!;
    await pump(tester, s, const SettingsScreen());
    await tester.tap(find.text('WhatsApp'));
    await settle(tester);
    expect(find.text('Potongan per pcs (opsional)'), findsOneWidget);
    await finish(tester, s);
  });
}
