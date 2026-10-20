import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/providers.dart';
import 'package:hpp_app/data/repositories/order_repository.dart';
import 'package:hpp_app/presentation/orders/order_detail_screen.dart';
import 'package:hpp_app/presentation/orders/order_form_screen.dart';
import 'package:hpp_app/presentation/orders/orders_screen.dart';
import 'package:hpp_app/presentation/theme.dart';

import '../support/seed.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(360, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: buildAppTheme(), home: screen),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.runAsync(db.close);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<(Seed, String)> seedOrder(WidgetTester tester) async {
    final result = await tester.runAsync(() async {
      final s = await Seed.create();
      final mitra = await s.channel('Mitra 20%', '20');
      final now = DateTime.now();
      final id = await s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: DateTime(now.year, now.month, now.day, 23, 59),
          customerName: 'Bu Rina',
          channelId: mitra,
          items: [
            OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
          ],
        ),
      );
      return (s, id);
    });
    return result!;
  }

  testWidgets('kalender pesanan menampilkan pesanan dan kebutuhan produksi', (
    tester,
  ) async {
    final (s, _) = await seedOrder(tester);
    await _pump(tester, s.db, const OrdersScreen());

    expect(find.text('Bu Rina'), findsOneWidget);
    expect(find.text('10 brownies'), findsOneWidget);
    expect(find.text('Mitra 20% · Belum bayar'), findsOneWidget);
    expect(find.text('Baru'), findsWidgets);
    expect(find.text('Kebutuhan produksi'), findsOneWidget);
    expect(find.text('pesan 10 · buat 10'), findsOneWidget);

    await tester.tap(find.text('Daftar'));
    await tester.pump();
    expect(find.text('Hari ini · 1'), findsOneWidget);

    await _close(tester, s.db);
  });

  testWidgets('detail pesanan: laba, pembayaran, dan ubah status', (
    tester,
  ) async {
    final (s, id) = await seedOrder(tester);
    await _pump(tester, s.db, OrderDetailScreen(id: id));

    expect(find.text('Bu Rina'), findsOneWidget);
    expect(find.text('Rp80.000'), findsWidgets);
    expect(find.text('−Rp16.000'), findsOneWidget);
    expect(find.text('Rp15.650'), findsOneWidget);
    expect(find.text('Belum bayar'), findsOneWidget);

    await tester.tap(find.text('Mulai diproses'));
    await _settle(tester);
    expect(find.text('Diproses'), findsOneWidget);
    expect(find.text('Tandai siap'), findsOneWidget);

    await _close(tester, s.db);
  });

  testWidgets('form ubah pesanan memuat isian dan menghitung laba', (
    tester,
  ) async {
    final (s, id) = await seedOrder(tester);
    await _pump(tester, s.db, OrderFormScreen(id: id));

    expect(find.text('Ubah pesanan'), findsOneWidget);
    expect(find.text('Brownies'), findsOneWidget);
    expect(find.text('Perkiraan laba'), findsOneWidget);
    expect(find.text('Rp15.650'), findsOneWidget);

    await tester.tap(find.byTooltip('Tambah'));
    await tester.pump();
    // 11 pcs: omzet 88.000 − potongan 17.600 − HPP 53.185 = 17.215.
    expect(find.text('Rp17.215'), findsOneWidget);

    await _close(tester, s.db);
  });
}
