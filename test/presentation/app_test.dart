import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/sync/sync_engine.dart';
import 'package:buat_usaha/presentation/app.dart';
import 'package:buat_usaha/services/sync_controller.dart';

import '../support/fake_account_gateway.dart';
import '../support/fake_remote_store.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeRemoteStore remote;

  setUp(() => remote = FakeRemoteStore());

  Future<void> pumpApp(
    WidgetTester tester,
    AppDatabase db, {
    FakeAccountGateway? gateway,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          if (gateway != null) ...[
            accountGatewayProvider.overrideWithValue(gateway),
            remoteStoreProvider.overrideWithValue(remote),
          ],
        ],
        child: const HppApp(),
      ),
    );
    await _settle(tester);
  }

  Future<void> finish(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  testWidgets('tanpa Firebase: berhenti di layar Masuk dengan pesannya', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpApp(tester, db);

    expect(find.text('BuatUsaha'), findsOneWidget);
    expect(find.textContaining('belum tersambung ke Firebase'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Masuk dengan Google'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.widgetWithText(AppBar, 'Beranda'), findsNothing);
    await finish(tester, db);
  });

  testWidgets('akun baru: masuk → onboarding → navigasi bawah antar tab', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = FakeAccountGateway();
    await pumpApp(tester, db, gateway: gateway);

    // Belum masuk → layar Masuk (FR-10.1).
    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('HPP per pcs otomatis dari resep'), findsOneWidget);
    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    // Akun dan HP kosong → onboarding (FR-8.4, FR-10.13).
    expect(find.text('Selamat datang'), findsOneWidget);
    expect(remote.live(rina.uid, 'businesses'), hasLength(1));
    await tester.enterText(
      find.widgetWithText(TextField, 'Nama usaha'),
      'Dapur Bu Rina',
    );
    await tester.tap(find.text('Lanjut'));
    await _settle(tester);
    expect(find.text('Pengingat pesanan'), findsOneWidget);
    await tester.tap(find.text('Nanti saja'));
    await _settle(tester);
    expect(find.text('Menu pertama'), findsOneWidget);
    await tester.tap(find.text('Lewati, ke Beranda'));
    await _settle(tester);

    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    expect(find.text('Dapur Bu Rina'), findsOneWidget);
    expect(find.text('Catat cepat'), findsOneWidget);
    expect(appTabs.map((t) => t.label), [
      'Beranda',
      'Pesanan',
      'Menu',
      'Bahan',
      'Laporan',
    ]);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Menu'));
    await _settle(tester);
    expect(find.text('Belum ada menu'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Pesanan'));
    await _settle(tester);
    expect(find.text('Kalender'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Laporan'));
    await _settle(tester);
    expect(find.text('Per menu'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('pengguna versi lama: data HP diunggah lalu Mulai pakai', (
    tester,
  ) async {
    final seed = (await tester.runAsync(Seed.create))!;
    await pumpApp(tester, seed.db, gateway: FakeAccountGateway());

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    expect(find.text('Data tersimpan di akunmu'), findsOneWidget);
    expect(find.text('rina.kusuma.wardhani@gmail.com'), findsOneWidget);
    expect(remote.live(rina.uid, 'ingredients'), hasLength(5));
    await tester.tap(find.text('Mulai pakai'));
    await _settle(tester);
    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    await finish(tester, seed.db);
  });

  testWidgets('HP baru: data akun diunduh lalu Mulai pakai', (tester) async {
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    final db = AppDatabase(NativeDatabase.memory());
    await pumpApp(tester, db, gateway: FakeAccountGateway());

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    expect(find.text('Data usahamu siap'), findsOneWidget);
    await tester.tap(find.text('Mulai pakai'));
    await _settle(tester);
    // Usaha dari akun sudah lewat onboarding → langsung Beranda.
    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    expect(find.text('Selamat datang'), findsNothing);
    final ingredients = await tester.runAsync(
      () => db.select(db.ingredients).get(),
    );
    expect(ingredients, hasLength(5));
    await finish(tester, db);
  });

  testWidgets('keduanya berisi data: Batal dan keluar kembali ke Masuk', (
    tester,
  ) async {
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    final seed = (await tester.runAsync(Seed.create))!;
    final gateway = FakeAccountGateway();
    await pumpApp(tester, seed.db, gateway: gateway);

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);
    expect(find.text('Akun ini sudah berisi data'), findsOneWidget);
    expect(
      find.textContaining('Di HP ini ada 5 bahan dan 1 menu.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Batal dan keluar'));
    await _settle(tester);

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(gateway.current, isNull);
    final ingredients = await tester.runAsync(
      () => seed.db.select(seed.db.ingredients).get(),
    );
    expect(ingredients, hasLength(5));
    await finish(tester, seed.db);
  });

  testWidgets('keduanya berisi data: Gabungkan keduanya', (tester) async {
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    final seed = (await tester.runAsync(Seed.create))!;
    await pumpApp(tester, seed.db, gateway: FakeAccountGateway());

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);
    await tester.tap(find.text('Gabungkan keduanya'));
    await _settle(tester);

    expect(find.text('Data sudah digabung'), findsOneWidget);
    final ingredients = await tester.runAsync(
      () => seed.db.select(seed.db.ingredients).get(),
    );
    expect(ingredients, hasLength(10));
    await finish(tester, seed.db);
  });

  testWidgets('dibatalkan di pilihan akun Google: tetap di Masuk', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final gateway = FakeAccountGateway(null, null);
    await pumpApp(tester, db, gateway: gateway);

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.textContaining('Masuk dibatalkan'), findsOneWidget);
    await finish(tester, db);
  });

  testWidgets('backup baru dipulihkan: isi akun diganti isi backup', (
    tester,
  ) async {
    // Akun berisi data lama; HP berisi backup yang dilepas dari akun.
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    final seed = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(() => SyncEngine.markOverwrite(seed.db));
    await pumpApp(tester, seed.db, gateway: FakeAccountGateway(rina));

    expect(find.text('Isi akun sudah diganti'), findsOneWidget);
    // Bahan HP lain dihapus dari akun; tinggal bahan dari backup.
    final mine = (await tester.runAsync(
      () => seed.db.select(seed.db.ingredients).get(),
    ))!;
    expect(
      remote.live(rina.uid, 'ingredients').map((r) => r['id']).toSet(),
      mine.map((i) => i.id).toSet(),
    );
    await tester.tap(find.text('Mulai pakai'));
    await _settle(tester);
    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    await finish(tester, seed.db);
  });

  testWidgets('sudah masuk sebelumnya: langsung ke Beranda', (tester) async {
    final seed = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(seed.db, remote).link(rina.uid, LinkPlan.upload),
    );
    await pumpApp(tester, seed.db, gateway: FakeAccountGateway(rina));

    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);
    await finish(tester, seed.db);
  });
}
