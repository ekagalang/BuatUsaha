import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/sync/sync_engine.dart';
import 'package:buat_usaha/presentation/settings/account_section.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/services/account_service.dart';
import 'package:buat_usaha/services/sync_controller.dart';

import '../support/fake_remote_store.dart';
import '../support/seed.dart';

const _rina = AccountUser(
  uid: 'akun-rina',
  name: 'Rina Kusuma Wardhani Pratiwi',
  email: 'rina.kusuma.wardhani@gmail.com',
);

/// Login Google tiruan.
class FakeAccountGateway implements AccountGateway {
  FakeAccountGateway([this._current]);

  AccountUser? _current;
  final _changes = StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get current => _current;

  @override
  Stream<AccountUser?> changes() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<AccountUser?> signIn() async {
    _current = _rina;
    _changes.add(_current);
    return _current;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }
}

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

  setUp(() => remote = FakeRemoteStore());

  Future<void> pump(
    WidgetTester tester, {
    AccountGateway? gateway,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(seed.db),
          if (gateway != null) ...[
            accountGatewayProvider.overrideWithValue(gateway),
            remoteStoreProvider.overrideWithValue(remote),
          ],
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

  testWidgets('tanpa Firebase: tombol masuk tidak aktif', (tester) async {
    seed = (await tester.runAsync(Seed.create))!;
    await pump(tester);

    expect(find.text('Akun dan sinkron'), findsOneWidget);
    expect(
      find.text('Belum bisa dipakai di versi ini: Firebase belum dipasang.'),
      findsOneWidget,
    );
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Masuk dengan Google'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('masuk dengan Google di akun kosong: data diunggah', (
    tester,
  ) async {
    seed = (await tester.runAsync(Seed.create))!;
    await pump(tester, gateway: FakeAccountGateway());

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    expect(find.text(_rina.name!), findsOneWidget);
    expect(find.text(_rina.email!), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('Tersinkron'), findsOneWidget);
    expect(find.text('Tidak ada'), findsOneWidget);
    expect(find.textContaining('Hari ini '), findsOneWidget);
    expect(find.textContaining('Data tersinkron.'), findsOneWidget);
    expect(remote.live(_rina.uid, 'ingredients'), hasLength(5));
    expect(remote.profiles[_rina.uid]?['email'], _rina.email);
    await finish(tester);
  });

  testWidgets('akun sudah berisi data lain: pilih gabungkan', (tester) async {
    // HP lain sudah mengunggah datanya ke akun yang sama.
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(_rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    seed = (await tester.runAsync(Seed.create))!;
    await pump(tester, gateway: FakeAccountGateway());

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);

    expect(find.text('Akun ini sudah berisi data'), findsOneWidget);
    expect(
      find.textContaining('Di HP ini ada 5 bahan dan 1 menu.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Gabungkan keduanya'));
    await _settle(tester);

    expect(find.text('Akun ini sudah berisi data'), findsNothing);
    expect(find.text('Tersinkron'), findsOneWidget);
    final ingredients = await tester.runAsync(
      () => seed.db.select(seed.db.ingredients).get(),
    );
    expect(ingredients, hasLength(10));
    await finish(tester);
  });

  testWidgets('batal di dialog: tetap belum masuk', (tester) async {
    final other = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(other.db, remote).link(_rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(other.db.close);
    seed = (await tester.runAsync(Seed.create))!;
    final gateway = FakeAccountGateway();
    await pump(tester, gateway: gateway);

    await tester.tap(find.text('Masuk dengan Google'));
    await _settle(tester);
    await tester.tap(find.text('Batal'));
    await _settle(tester);

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(gateway.current, isNull);
    await finish(tester);
  });

  testWidgets('keluar akun, data tetap di HP', (tester) async {
    seed = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(seed.db, remote).link(_rina.uid, LinkPlan.upload),
    );
    await pump(tester, gateway: FakeAccountGateway(_rina));
    expect(find.text('Tersinkron'), findsOneWidget);

    await tester.tap(find.text('Keluar dari akun'));
    await _settle(tester);
    expect(find.text('Keluar dari akun?'), findsOneWidget);
    await tester.tap(find.text('Keluar, data tetap di HP'));
    await _settle(tester);

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(
      find.text('Keluar dari akun. Data tetap di HP ini.'),
      findsOneWidget,
    );
    final business = (await tester.runAsync(
      () => seed.db.select(seed.db.businesses).getSingle(),
    ))!;
    expect(business.ownerUid, isNull);
    expect(
      await tester.runAsync(() => seed.db.select(seed.db.ingredients).get()),
      hasLength(5),
    );
    await finish(tester);
  });

  testWidgets('kartu akun dan dialog tidak terpotong dengan huruf 130%', (
    tester,
  ) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    seed = (await tester.runAsync(Seed.create))!;
    await tester.runAsync(
      () => SyncEngine(seed.db, remote).link(_rina.uid, LinkPlan.upload),
    );
    await tester.runAsync(
      () => seed.stock.updateIngredient(seed.ids['gula']!, name: 'Gula aren'),
    );
    // Tanpa internet: perubahan menunggu dan pesan gagal tampil.
    remote.offline = true;
    await pump(tester, gateway: FakeAccountGateway(_rina), textScale: 1.3);
    expect(find.text('Belum terkirim'), findsOneWidget);
    expect(find.text('1 perubahan'), findsOneWidget);
    expect(find.textContaining('Sinkron gagal'), findsOneWidget);

    await tester.tap(find.text('Keluar dari akun'));
    await _settle(tester);
    expect(find.text('Keluar dan hapus data dari HP ini'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await _settle(tester);
    await finish(tester);
  });
}
