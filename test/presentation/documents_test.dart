import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/providers.dart';
import 'package:buat_usaha/data/repositories/expense_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/report_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/presentation/documents/logo_image.dart';
import 'package:buat_usaha/presentation/documents/pdf_documents.dart';
import 'package:buat_usaha/presentation/documents/receipt.dart';
import 'package:buat_usaha/presentation/documents/report_csv.dart';
import 'package:buat_usaha/presentation/orders/order_detail_screen.dart';
import 'package:buat_usaha/presentation/reports/reports_screen.dart';
import 'package:buat_usaha/presentation/settings/settings_screen.dart';
import 'package:buat_usaha/presentation/theme.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/fake_updates.dart';
import '../support/seed.dart';

/// Profil usaha lengkap dan pesanan antar 10 brownies: diskon Rp5.000,
/// ongkir Rp10.000, DP Rp20.000.
Future<(Seed, String)> _seed() async {
  final s = await Seed.create();
  await s.business.updateBusiness(
    s.businessId,
    const BusinessesCompanion(
      name: Value('Dapur Bu Rina'),
      phoneWa: Value('0811111'),
      address: Value('Jl. Kenanga 5, Bandung'),
      paymentInfo: Value('BCA 1234567 a.n. Rina'),
    ),
  );
  final id = await s.orders.createOrder(
    s.businessId,
    OrderInput(
      dueAt: DateTime(2026, 10, 23, 13),
      customerName: 'Bu Sari',
      customerPhone: '0812-3456-789',
      fulfillment: Fulfillment.delivery,
      deliveryAddress: 'Jl. Melati 3',
      discount: 5000,
      shippingFee: 10000,
      note: 'Tanpa kacang',
      items: [OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000)],
    ),
  );
  await s.orders.addPayment(id, amount: 20000, method: PaymentMethod.transfer);
  return (s, id);
}

Future<Business> _business(Seed s) => s.business.watch(s.businessId).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('nota', () {
    test('teks nota belum lunas: total, sisa, info pembayaran', () async {
      final (s, id) = await _seed();
      addTearDown(s.close);
      final text = receiptText(
        Receipt.of(await _business(s), await s.orders.loadOrder(id)),
      );
      expect(text, startsWith('*Dapur Bu Rina*\nNota PO-'));
      expect(text, contains('Kirim: Jumat, 23 Oktober 2026 13.00'));
      expect(text, contains('Pelanggan: Bu Sari\nAlamat: Jl. Melati 3'));
      expect(text, contains('Brownies  10 × Rp8.000 = Rp80.000'));
      expect(
        text,
        contains(
          'Subtotal: Rp80.000\nDiskon: −Rp5.000\nOngkir: Rp10.000\n'
          '*Total: Rp85.000*\nSudah dibayar: Rp20.000\n*Sisa: Rp65.000*',
        ),
      );
      expect(text, contains('Pembayaran:\nBCA 1234567 a.n. Rina'));
      expect(text, contains('Catatan: Tanpa kacang'));
      expect(text, endsWith('Terima kasih sudah memesan.'));
    });

    test('lunas: tanda LUNAS tanpa info pembayaran', () async {
      final (s, id) = await _seed();
      addTearDown(s.close);
      await s.orders.addPayment(
        id,
        amount: 65000,
        method: PaymentMethod.cash,
        kind: PaymentKind.settlement,
      );
      await s.business.updateBusiness(
        s.businessId,
        const BusinessesCompanion(receiptNote: Value('Sampai jumpa lagi!')),
      );
      final text = receiptText(
        Receipt.of(await _business(s), await s.orders.loadOrder(id)),
      );
      expect(text, contains('*Total: Rp85.000*\n*LUNAS*'));
      expect(text, isNot(contains('Pembayaran:')));
      expect(text, isNot(contains('Sisa')));
      expect(text, endsWith('Sampai jumpa lagi!'));
    });

    test('nomor WhatsApp dan tautan wa.me', () {
      expect(waNumber('0812-3456-789'), '628123456789');
      expect(waNumber('+62 812 3456'), '628123456');
      expect(waNumber('812345'), '62812345');
      expect(waNumber(' '), isNull);
      expect(waNumber(null), isNull);
      expect(
        whatsappUrl('62812', 'Nota *A*\nRp1.000'),
        'https://wa.me/62812?text=Nota%20*A*%0ARp1.000',
      );
    });

    test('PDF A6 dan struk 58 mm, dengan logo', () async {
      final (s, id) = await _seed();
      addTearDown(s.close);
      final logo = encodeLogo(
        img.encodePng(img.Image(width: 900, height: 300)),
      )!;
      await s.business.updateBusiness(
        s.businessId,
        BusinessesCompanion(logoData: Value(logo)),
      );
      final fonts = await PdfFonts.load();
      final view = await s.orders.loadOrder(id);
      for (final size in ReceiptSize.values) {
        await s.business.updateBusiness(
          s.businessId,
          BusinessesCompanion(receiptSize: Value(size)),
        );
        final receipt = Receipt.of(await _business(s), view);
        expect(receipt.size, size);
        expect(receipt.logo, isNotNull);
        final pdf = await receiptPdf(receipt, fonts);
        expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      }
    });

    test('logo diperkecil ke 256 px dan ≤ 100 KB; bukan gambar ditolak', () {
      final encoded = encodeLogo(
        img.encodePng(img.Image(width: 1200, height: 600)),
      )!;
      final bytes = base64Decode(encoded);
      expect(bytes.length, lessThanOrEqualTo(logoMaxBytes));
      final decoded = img.decodeJpg(bytes)!;
      expect((decoded.width, decoded.height), (256, 128));
      expect(encodeLogo(utf8.encode('bukan gambar')), isNull);
    });
  });

  group('ekspor laporan', () {
    Future<(Seed, ReportRepository)> seedPeriod() async {
      final (s, id) = await _seed();
      await s.products.recordProduction(
        s.brownies,
        batchQty: d('1'),
        at: DateTime.utc(2026, 10, 15),
      );
      await s.orders.completeOrder(id, at: DateTime(2026, 10, 21, 10));
      // Pesanan yang belum selesai tidak ikut.
      await s.orders.createOrder(
        s.businessId,
        OrderInput(
          dueAt: DateTime(2026, 10, 25, 10),
          items: [
            OrderItemInput(productId: s.brownies, qty: 2, unitPrice: 8000),
          ],
        ),
      );
      await s.stock.recordPurchase(
        s.businessId,
        PurchaseInput(
          purchasedAt: DateTime(2026, 10, 20, 7),
          note: 'Pasar; pagi',
          lines: [
            PurchaseLineInput(
              ingredientId: s.ids['tepung']!,
              qty: d('1.5'),
              unitName: 'kg',
              factorToBase: Decimal.fromInt(1000),
              totalPrice: 18000,
            ),
          ],
        ),
      );
      final expenses = ExpenseRepository(s.db);
      final category =
          (await expenses.watchCategories(s.businessId).first).first;
      await expenses.addExpense(
        s.businessId,
        categoryId: category.id,
        amount: 50000,
        spentAt: DateTime(2026, 10, 2, 9),
        note: 'Bayar "token"',
      );
      return (s, ReportRepository(s.db));
    }

    final from = DateTime(2026, 10);
    final to = DateTime(2026, 11);

    test('CSV: empat file, titik koma, desimal koma, BOM', () async {
      final (s, repo) = await seedPeriod();
      addTearDown(s.close);
      final files = reportCsv(
        await repo.exportData(s.businessId, from, to),
        from,
        to,
      );
      expect(files.map((f) => f.name), [
        'pesanan-2026-10-01_2026-10-31.csv',
        'item-terjual-2026-10-01_2026-10-31.csv',
        'belanja-2026-10-01_2026-10-31.csv',
        'pengeluaran-2026-10-01_2026-10-31.csv',
      ]);
      List<String> rows(int i) => files[i].content.trim().split('\r\n');

      expect(files[0].content, startsWith('﻿No pesanan;Selesai;Jenis;'));
      expect(rows(0), hasLength(2));
      expect(
        rows(0)[1],
        endsWith(
          ';2026-10-21 10:00;Pesanan;Bu Sari;Langsung;80000;5000;10000;'
          '85000;0;20000;DP',
        ),
      );
      // Omzet setelah diskon 75.000; HPP 10 × 4.835.
      expect(
        rows(1)[1],
        endsWith(';2026-10-21 10:00;Brownies;10;8000;75000;0;48350;26650'),
      );
      expect(rows(2)[1], '2026-10-20 07:00;;Tepung;1,5;kg;18000;"Pasar; pagi"');
      expect(rows(3)[1], endsWith(';Tidak;50000;"Bayar ""token"""'));
    });

    test('ringkasan PDF A4', () async {
      final (s, repo) = await seedPeriod();
      addTearDown(s.close);
      final pdf = await reportPdf(
        businessName: 'Dapur Bu Rina',
        periodLabel: 'Oktober 2026',
        report: await repo.periodReport(s.businessId, from, to),
        data: await repo.exportData(s.businessId, from, to),
        fonts: await PdfFonts.load(),
        printedAt: DateTime(2026, 10, 31, 20),
      );
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
    });
  });

  group('layar', () {
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
      FakeAppPlatform? platform,
    }) async {
      await tester.binding.setSurfaceSize(const Size(360, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => home)],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(s.db),
            if (platform != null)
              appPlatformProvider.overrideWithValue(platform),
          ],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
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

    testWidgets('detail pesanan: lembar nota dan kirim ke WhatsApp', (
      tester,
    ) async {
      final (s, id) = (await tester.runAsync(_seed))!;
      final platform = FakeAppPlatform();
      await pump(tester, s, OrderDetailScreen(id: id), platform: platform);

      await tester.tap(find.byTooltip('Nota'));
      await settle(tester);
      expect(find.text('Kirim ke WhatsApp pelanggan'), findsOneWidget);
      expect(find.text('0812-3456-789'), findsOneWidget);
      expect(find.text('Bagikan teks nota'), findsOneWidget);
      expect(find.text('A6 · ukuran diubah di Pengaturan'), findsOneWidget);

      await tester.tap(find.text('Kirim ke WhatsApp pelanggan'));
      await settle(tester);
      final url = platform.opened.single;
      expect(url, startsWith('https://wa.me/628123456789?text='));
      expect(
        Uri.parse(url).queryParameters['text'],
        contains('*Sisa: Rp65.000*'),
      );
      await finish(tester, s);
    });

    testWidgets('pengaturan: info pembayaran dan ukuran nota disimpan', (
      tester,
    ) async {
      final s = (await tester.runAsync(Seed.create))!;
      await pump(tester, s, const SettingsScreen());

      expect(find.text('Logo untuk nota (opsional)'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Info pembayaran'),
        'QRIS: minta lewat WA',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Alamat (opsional)'),
        'Jl. Kenanga 5',
      );
      await tester.tap(find.text('Simpan profil'));
      await settle(tester);
      await tester.tap(find.text('Struk 58 mm'));
      await settle(tester);

      final business = (await tester.runAsync(() => _business(s)))!;
      expect(business.paymentInfo, 'QRIS: minta lewat WA');
      expect(business.address, 'Jl. Kenanga 5');
      expect(business.receiptNote, isNull);
      expect(business.receiptSize, ReceiptSize.roll58);
      await finish(tester, s);
    });

    testWidgets('laporan: lembar ekspor untuk periode yang dibuka', (
      tester,
    ) async {
      final s = (await tester.runAsync(Seed.create))!;
      await pump(tester, s, const ReportsScreen());
      await tester.tap(find.text('Bulan'));
      await settle(tester);
      await tester.tap(find.byTooltip('Ekspor'));
      await settle(tester);
      final now = DateTime.now();
      expect(find.textContaining('Ekspor '), findsOneWidget);
      expect(find.textContaining('${now.year}'), findsWidgets);
      expect(find.text('Ringkasan PDF'), findsOneWidget);
      expect(find.text('Data CSV'), findsOneWidget);
      await finish(tester, s);
    });
  });
}
