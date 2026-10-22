import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/sync/sync_engine.dart';
import 'package:buat_usaha/presentation/settings/account_section.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/services/sync_controller.dart';

import '../support/screen.dart';
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
  late Seed seed;
  late FakeAccountGateway gateway;

  setUp(() {
    remote = FakeRemoteStore();
    gateway = FakeAccountGateway(rina);
  });

  /// HP berisi data contoh yang sudah terhubung dengan akun Rina.
  Future<void> linkedPhone(WidgetTester tester) async {
    seed = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(seed.db, remote).link(rina.uid, LinkPlan.upload),
    );
  }

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(seed.db),
          accountGatewayProvider.overrideWithValue(gateway),
          remoteStoreProvider.overrideWithValue(remote),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: const [AccountSection()],
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(seed.db.close);
  }

  testWidgets('kartu akun: nama, email, status, dan sinkron sekarang', (
    tester,
  ) async {
    await linkedPhone(tester);
    await pump(tester);

    expect(find.text('Akun dan sinkron'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);
    expect(find.text(rina.name!), findsOneWidget);
    expect(find.text(rina.email!), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('Tersinkron'), findsOneWidget);
    expect(find.text('Tidak ada'), findsOneWidget);
    expect(find.textContaining('Hari ini '), findsOneWidget);

    await tester.tap(find.text('Sinkron sekarang'));
    await _settle(tester);
    expect(find.text('Tersinkron.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('keluar akun menghapus data dari HP, data di akun tetap', (
    tester,
  ) async {
    await linkedPhone(tester);
    await pump(tester);

    await tester.tap(find.text('Keluar dari akun'));
    await _settle(tester);
    expect(find.text('Keluar dari akun?'), findsOneWidget);
    expect(find.textContaining('belum terkirim'), findsNothing);
    await tester.tap(find.text('Keluar dan hapus data dari HP ini'));
    await _settle(tester);

    expect(gateway.current, isNull);
    expect(
      find.text(
        'Keluar dari akun. Data di HP ini dihapus; di akun tetap aman.',
      ),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(() => seed.db.select(seed.db.ingredients).get()),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => seed.db.select(seed.db.businesses).get()),
      isEmpty,
    );
    expect(remote.live(rina.uid, 'ingredients'), hasLength(5));
    await finish(tester);
  });

  testWidgets('tanpa internet: peringatan perubahan belum terkirim (130%)', (
    tester,
  ) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    setScreenSize(tester, const Size(360, 1400));
    await linkedPhone(tester);
    await tester.runAsync(
      () => seed.stock.updateIngredient(seed.ids['gula']!, name: 'Gula aren'),
    );
    remote.offline = true;
    await pump(tester, textScale: 1.3);
    expect(find.text('Belum terkirim'), findsOneWidget);
    expect(find.text('1 perubahan'), findsOneWidget);
    expect(find.textContaining('Sinkron gagal'), findsOneWidget);

    await tester.tap(find.text('Keluar dari akun'));
    await _settle(tester);
    expect(
      find.textContaining('Ada 1 perubahan yang belum terkirim'),
      findsOneWidget,
    );
    expect(find.text('Keluar tanpa mengirim perubahan'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await _settle(tester);

    expect(gateway.current, rina);
    expect(
      await tester.runAsync(() => seed.db.select(seed.db.ingredients).get()),
      hasLength(5),
    );
    await finish(tester);
  });
}
