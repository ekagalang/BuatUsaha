import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/presentation/app.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('onboarding pertama kali lalu navigasi bawah antar tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const HppApp(),
      ),
    );
    await _settle(tester);

    // Database baru → onboarding (FR-8.4).
    expect(find.text('Selamat datang'), findsOneWidget);
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

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
