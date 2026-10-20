import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/presentation/app.dart';

void main() {
  testWidgets('navigasi bawah berpindah antar tab', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: HppApp()));
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
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Menu'), findsOneWidget);
  });
}
