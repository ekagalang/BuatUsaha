import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/providers.dart';
import 'package:hpp_app/presentation/app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('navigasi bawah berpindah antar tab', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const HppApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Beranda'), findsOneWidget);
    for (final tab in appTabs) {
      expect(
        find.widgetWithText(NavigationDestination, tab.label),
        findsOneWidget,
      );
    }

    expect(appTabs.map((t) => t.label), [
      'Beranda',
      'Pesanan',
      'Menu',
      'Bahan',
      'Laporan',
    ]);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Menu'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.widgetWithText(AppBar, 'Menu'), findsOneWidget);
    expect(find.text('Belum ada menu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  });
}
