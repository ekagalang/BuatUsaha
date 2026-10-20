import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/day_close_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/presentation/home/home_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_detail_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_form_screen.dart';
import 'package:buat_usaha/presentation/menu/menu_screen.dart';
import 'package:buat_usaha/presentation/orders/cost_correction_screen.dart';
import 'package:buat_usaha/presentation/orders/order_detail_screen.dart';
import 'package:buat_usaha/presentation/orders/order_form_screen.dart';
import 'package:buat_usaha/presentation/orders/orders_screen.dart';
import 'package:buat_usaha/presentation/reports/day_close_screen.dart';
import 'package:buat_usaha/presentation/reports/reports_screen.dart';
import 'package:buat_usaha/presentation/settings/settings_screen.dart';
import 'package:buat_usaha/presentation/stock/ingredient_detail_screen.dart';
import 'package:buat_usaha/presentation/stock/ingredients_screen.dart';
import 'package:buat_usaha/presentation/stock/purchase_form_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';

import '../support/seed.dart';

/// Data yang mengisi semua layar: produksi, pesanan hari ini, belanja salah
/// ketik yang sudah dikoreksi (pesanan lama terdampak), dan sisa menu.
class _Ids {
  _Ids(this.seed, this.order, this.purchase);

  final Seed seed;
  final String order;
  final String purchase;
}

Future<_Ids> _seed() async {
  final s = await Seed.create();
  final now = DateTime.now();
  final wrong = await s.stock.recordPurchase(
    s.businessId,
    PurchaseInput(
      purchasedAt: now.subtract(const Duration(days: 3)),
      note: 'Toko Makmur di Jalan Panjang Sekali Nomor 123',
      lines: [
        PurchaseLineInput(
          ingredientId: s.ids['tepung']!,
          qty: d('1'),
          unitName: 'kg',
          factorToBase: d('1000'),
          totalPrice: 140000,
        ),
      ],
    ),
  );
  await s.products.recordProduction(
    s.brownies,
    batchQty: d('1.5'),
    at: now.subtract(const Duration(days: 2)),
  );
  await s.orders.recordDirectSale(
    s.businessId,
    OrderInput(
      dueAt: now.subtract(const Duration(days: 1)),
      items: [OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000)],
    ),
  );
  final fixed = await s.stock.replacePurchase(
    wrong,
    PurchaseInput(
      purchasedAt: now.subtract(const Duration(days: 3)),
      lines: [
        PurchaseLineInput(
          ingredientId: s.ids['tepung']!,
          qty: d('1'),
          unitName: 'kg',
          factorToBase: d('1000'),
          totalPrice: 14000,
        ),
      ],
    ),
  );
  final mitra = await s.channel('Mitra Pesan Antar Panjang', '20');
  final order = await s.orders.createOrder(
    s.businessId,
    OrderInput(
      dueAt: DateTime(now.year, now.month, now.day, 23, 59),
      customerName: 'Ibu Kartika Sari Dewi Rahmawati',
      customerPhone: '081234567890',
      channelId: mitra,
      fulfillment: Fulfillment.delivery,
      deliveryAddress: 'Jl. Melati Raya No. 45, Kebayoran Baru',
      shippingFee: 15000,
      discount: 5000,
      items: [OrderItemInput(productId: s.brownies, qty: 12, unitPrice: 8000)],
    ),
  );
  await s.orders.addPayment(order, amount: 50000, method: PaymentMethod.qris);
  await s.stock.updateIngredient(s.ids['cokelat']!, minStock: d('500'));
  await DayCloseRepository(s.db, s.products).leftovers(s.businessId, now);
  return _Ids(s, order, fixed);
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

  final screens = <String, Widget Function(_Ids)>{
    'Beranda': (_) => const HomeScreen(),
    'Menu': (_) => const MenuScreen(),
    'Detail menu': (i) => MenuDetailScreen(id: i.seed.brownies),
    'Ubah resep': (i) => MenuFormScreen(id: i.seed.brownies),
    'Pesanan': (_) => const OrdersScreen(),
    'Ubah pesanan': (i) => OrderFormScreen(id: i.order),
    'Detail pesanan': (i) => OrderDetailScreen(id: i.order),
    'Laporan': (_) => const ReportsScreen(),
    'Tutup hari': (_) => const DayCloseScreen(),
    'Bahan': (_) => const IngredientsScreen(),
    'Detail bahan': (i) => IngredientDetailScreen(id: i.seed.ids['tepung']!),
    'Ubah belanja': (i) => PurchaseFormScreen(purchaseId: i.purchase),
    'Koreksi HPP': (_) => const CostCorrectionScreen(),
    'Pengaturan': (_) => const SettingsScreen(),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name tidak terpotong dengan huruf 130% di layar 360 dp', (
      tester,
    ) async {
      final ids = (await tester.runAsync(_seed))!;
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      await tester.binding.setSurfaceSize(const Size(360, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(ids.seed.db)],
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: build(ids),
          ),
        ),
      );
      await _settle(tester);
      // Layout yang meluap dilaporkan flutter_test sebagai kegagalan.

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await tester.runAsync(ids.seed.db.close);
    });
  }
}
