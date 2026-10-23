import 'dart:io';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/db/decimal_convert.dart';
import 'package:buat_usaha/data/repositories/archive_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/pricing_repository.dart';
import 'package:buat_usaha/data/repositories/product_repository.dart';
import 'package:buat_usaha/data/repositories/report_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/domain/costing/costing.dart';
import 'package:buat_usaha/domain/stock/units.dart';
import 'package:buat_usaha/presentation/menu/menu_drafts.dart';
import 'package:buat_usaha/services/backup_service.dart';
import 'package:buat_usaha/services/update_controller.dart';

import '../support/fake_updates.dart';
import '../support/seed.dart';

void main() {
  late Seed s;
  late ArchiveRepository archive;

  setUp(() async {
    s = await Seed.create();
    archive = ArchiveRepository(s.db, s.stock, s.products);
  });
  tearDown(() => s.close());

  Future<Ingredient> ingredient(String id) =>
      s.stock.watchIngredient(id).first.then((v) => v.ingredient);

  Future<PeriodReport> october() =>
      ReportRepository(s.db)
          .periodReport(s.businessId, DateTime(2026, 10), DateTime(2026, 11));

  Future<String> estimateOnly(String name) async =>
      (await s.stock.createIngredient(
        businessId: s.businessId,
        name: name,
        baseUnit: BaseUnit.pcs,
        estimatedUnitCost: d('1250'),
        at: DateTime(2026, 10, 2),
      )).id;

  group('stok awal (FR-20.6)', () {
    test('data lama: stok pertama lewat opname dijadikan stok awal', () async {
      final roti = await estimateOnly('Roti burger');
      await s.stock.recordOpname(
        roti,
        countedQty: d('20'),
        at: DateTime(2026, 10, 3),
      );
      await s.stock.recordAdjustment(
        roti,
        qtyBase: d('-2'),
        at: DateTime(2026, 10, 3, 1),
      );
      // Sebelum perbaikan: selisih opname dan penyesuaian ikut laba.
      expect((await october()).materialLoss, -22500);

      await s.db
          .into(s.db.syncState)
          .insert(
            SyncStateCompanion.insert(
              entity: AppDatabase.openingFixKey,
              lastPulledAt: Value(DateTime.now().toUtc()),
            ),
          );
      expect(await s.stock.runOpeningFix(s.businessId), 1);
      final fixed = await ingredient(roti);
      expect(fixed.currentStock, 18);
      expect(fixed.avgUnitCost, 1250);
      expect((await october()).materialLoss, 0);
      final card = await s.stock.watchStockCard(roti).first;
      expect(
        card
            .where((e) => !e.cancelled && !e.isReversal)
            .map((e) => e.movement.type),
        containsAll([MovementType.opening]),
      );
      // Bahan dengan belanja tidak tersentuh; perbaikan hanya sekali.
      expect(await s.stock.runOpeningFix(s.businessId), 0);
    });

    test('isi stok awal hanya mengganti stok awal, tidak masuk laba', () async {
      final roti = await estimateOnly('Roti burger');
      expect(await s.stock.canSetInitialStock(roti), isTrue);
      await s.stock.setInitialStock(
        roti,
        qtyBase: d('20'),
        unitCost: d('1250'),
      );
      await s.stock.setInitialStock(
        roti,
        qtyBase: d('24'),
        unitCost: d('1200'),
      );
      final r = await ingredient(roti);
      expect(r.currentStock, 24);
      expect(r.avgUnitCost, 1200);
      expect((await october()).materialLoss, 0);
      await s.stock.recordWaste(roti, qtyBase: d('1'));
      expect(await s.stock.canSetInitialStock(roti), isFalse);
    });

    test('penyesuaian stok ikut dihitung di laporan', () async {
      await s.stock.recordAdjustment(
        s.ids['telur']!,
        qtyBase: d('-1'),
        at: DateTime(2026, 10, 5),
      );
      expect((await october()).materialLoss, 2000);
    });
  });

  test('potongan channel Rupiah per pcs (FR-20.5)', () async {
    expect(
      channelFee(
        itemsTotal: 80000,
        commissionPct: Decimal.zero,
        feePerPcs: 1500,
        pcs: 10,
      ),
      15000,
    );
    await s.orders.saveChannel(
      s.businessId,
      name: 'Mitra kantin',
      commissionPct: Decimal.zero,
      feePerPcs: 1500,
    );
    final mitra = (await s.orders.watchChannels(s.businessId).first).firstWhere(
      (c) => c.name == 'Mitra kantin',
    );
    final id = await s.orders.createOrder(
      s.businessId,
      OrderInput(
        dueAt: DateTime(2026, 10, 25, 10),
        channelId: mitra.id,
        items: [
          OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
        ],
      ),
    );
    expect((await s.orders.loadOrder(id)).order.channelFee, 15000);
    // Saran: (8.000 + 1.500) ÷ 1 = 9.500.
    expect(
      suggestChannelPrice(
        directPrice: 8000,
        commissionPct: Decimal.zero,
        feePerPcs: 1500,
        avgPcsPerOrder: Decimal.one,
      ),
      9500,
    );
  });

  group('arsip dan hapus (FR-20.2, FR-20.4)', () {
    test('bahan tanpa riwayat dihapus permanen', () async {
      final saos = await estimateOnly('Saos tomat');
      final usage = await archive.ingredientUsage(saos);
      expect(usage.hasHistory, isFalse);
      await archive.removeIngredient(saos, action: RemoveAction.delete);
      final rows = await (s.db.select(
        s.db.ingredients,
      )..where((t) => t.id.equals(saos))).get();
      expect(rows, isEmpty);
    });

    test('bahan di resep: arsip, hapus dari resep, sisa jadi rusak', () async {
      final telur = s.ids['telur']!;
      final usage = await archive.ingredientUsage(telur);
      expect(usage.menus.map((m) => m.name), ['Brownies']);
      final before = (await s.product(s.brownies)).hppPerPcs;

      await archive.removeIngredient(
        telur,
        action: RemoveAction.archive,
        wasteRemaining: true,
        removeFromRecipes: true,
      );
      final t = await ingredient(telur);
      expect(t.archivedAt, isNotNull);
      expect(t.currentStock, 0);
      // Telur 4 × Rp2.000 per resep 20 pcs keluar dari HPP.
      expect((await s.product(s.brownies)).hppPerPcs, before - d('400'));
      final views = await s.stock.watchIngredients(s.businessId).first;
      expect(
        views.firstWhere((v) => v.ingredient.id == telur).isArchived,
        isTrue,
      );

      await archive.restoreIngredient(telur);
      expect((await ingredient(telur)).archivedAt, isNull);
    });

    test('bahan dihapus dengan riwayat: tidak tampil, riwayat tetap', () async {
      final gula = s.ids['gula']!;
      await s.stock.recordWaste(gula, qtyBase: d('10'));
      await archive.removeIngredient(gula, action: RemoveAction.delete);
      final views = await s.stock.watchIngredients(s.businessId).first;
      expect(views.any((v) => v.ingredient.id == gula), isFalse);
      expect(await s.stock.watchStockCard(gula).first, isNotEmpty);
    });

    test(
      'menu: tanpa riwayat hapus permanen, dengan pesanan diarsipkan',
      () async {
        final cookies = await s.products.createProduct(
          s.businessId,
          s.browniesInput(name: 'Cookies'),
        );
        await archive.removeProduct(cookies, action: RemoveAction.delete);
        expect(
          await (s.db.select(
            s.db.products,
          )..where((t) => t.id.equals(cookies))).get(),
          isEmpty,
        );

        final order = await s.orders.createOrder(
          s.businessId,
          OrderInput(
            dueAt: DateTime(2026, 10, 25, 10),
            items: [
              OrderItemInput(productId: s.brownies, qty: 2, unitPrice: 8000),
            ],
          ),
        );
        final usage = await archive.productUsage(s.brownies);
        expect(usage.hasHistory, isTrue);
        expect(usage.openOrders, [
          (await s.orders.loadOrder(order)).order.orderNo,
        ]);
        await archive.removeProduct(s.brownies, action: RemoveAction.archive);
        expect((await s.product(s.brownies)).isArchived, isTrue);
        // Pesanan tetap berjalan.
        expect(
          (await s.orders.loadOrder(order)).lines.single.product.name,
          'Brownies',
        );
        await archive.removeProduct(s.brownies, action: RemoveAction.delete);
        final listed = await s.products.watchProducts(s.businessId).first;
        expect(listed.any((p) => p.product.id == s.brownies), isFalse);
      },
    );
  });

  group('satuan (FR-20.2, FR-20.3)', () {
    test('ganti cara hitung pcs → g dengan konversi', () async {
      final telur = s.ids['telur']!;
      final before = (await s.product(s.brownies)).hppPerPcs;
      await s.stock.changeBaseUnit(telur, BaseUnit.g, factor: d('60'));
      final t = await ingredient(telur);
      expect(t.baseUnit, BaseUnit.g);
      expect(t.currentStock, 600);
      expect(dec(t.avgUnitCost!).round(scale: 2), d('33.33'));
      final recipe = await s.products.inputOf(s.brownies);
      expect(
        recipe.recipe.firstWhere((r) => r.ingredientId == telur).qtyBase,
        d('240'),
      );
      expect(
        (await s.product(s.brownies)).hppPerPcs.round(scale: 0),
        before.round(scale: 0),
      );
    });

    test(
      'nama satuan jumlah, satuan sama, satuan bawaan disembunyikan',
      () async {
        final telur = s.ids['telur']!;
        await s.stock.updateIngredient(telur, countUnit: 'butir');
        expect((await ingredient(telur)).unitLabel, 'butir');

        await s.stock.addCustomUnit(
          telur,
          unitName: 'Pack',
          factorToBase: d('10'),
        );
        await s.stock.addCustomUnit(
          telur,
          unitName: ' pack ',
          factorToBase: d('12'),
        );
        await s.stock.setUnitHidden(telur, 'lusin', hidden: true);
        final options = await s.stock.unitOptions(telur);
        expect(options.map((o) => o.name), ['butir', 'kodi', 'Pack']);
        expect(options.last.factorToBase, d('12'));
        expect(await s.stock.unitLibrary(s.businessId), contains('Pack'));
      },
    );

    test('satuan dapur: baku untuk cair, resep menyimpan satuan', () async {
      final santan = await s.stock.createIngredient(
        businessId: s.businessId,
        name: 'Santan',
        baseUnit: BaseUnit.ml,
      );
      final cair = await s.stock.unitOptions(santan.id, forRecipe: true);
      expect(cair.firstWhere((u) => u.name == 'sdm').factorToBase, d('15'));
      expect(normalizeUnitName('  SDM '), 'sdm');

      final tepung = s.ids['tepung']!;
      await s.stock.addCustomUnit(
        tepung,
        unitName: 'sdm',
        factorToBase: d('8'),
        forRecipe: true,
      );
      expect(
        (await s.stock.unitOptions(tepung)).any((u) => u.name == 'sdm'),
        isFalse,
      );
      final input = s.browniesInput(name: 'Pancake');
      final id = await s.products.createProduct(
        s.businessId,
        ProductInput(
          name: input.name,
          sellingPrice: input.sellingPrice,
          yieldQty: input.yieldQty,
          recipe: [
            RecipeInput(
              ingredientId: tepung,
              qtyBase: d('24'),
              unitName: 'sdm',
              unitFactor: d('8'),
            ),
          ],
        ),
      );
      final saved = (await s.products.inputOf(id)).recipe.single;
      expect(saved.unitName, 'sdm');
      expect(saved.unitFactor, d('8'));
      expect(saved.qtyBase, d('24'));
    });
  });

  test('backup dari versi aplikasi lebih baru ditolak (FR-20.7)', () async {
    final dir = Directory.systemTemp.createTempSync('backup_baru');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = await BackupService.export(s.db, into: dir);
    final bytes = Uint8List.fromList(await file.readAsBytes());
    bytes[63] = 99;
    await file.writeAsBytes(bytes, flush: true);
    await expectLater(
      BackupService.inspect(file),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('lebih baru'),
        ),
      ),
    );
    expect(
      backupDateOf(File('buatusaha-backup-20261021-2217.sqlite')),
      DateTime(2026, 10, 21, 22, 17),
    );
  });

  test(
    'draf menu tersimpan di HP sampai disimpan atau dibuang (FR-20.1)',
    () async {
      final store = MemoryStore();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final drafts = container.read(menuDraftsProvider.notifier);
      await container.read(menuDraftsProvider.future);
      await drafts.save(
        MenuDraft(
          id: 'baru-1',
          savedAt: DateTime(2026, 10, 22, 10, 15),
          data: const {
            'name': 'Burger keju',
            'recipe': [
              {'ingredientId': 'x', 'qty': '1'},
            ],
          },
        ),
      );
      await drafts.save(
        MenuDraft(
          id: 'p1',
          productId: 'p1',
          savedAt: DateTime(2026, 10, 22, 11),
          data: const {'name': 'Brownies'},
        ),
      );
      expect(store.values.keys, contains('menu.drafts'));

      final again = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(again.dispose);
      final loaded = await again.read(menuDraftsProvider.future);
      expect(loaded.map((d) => d.name), ['Brownies', 'Burger keju']);
      expect(loaded.last.ingredientCount, 1);
      expect(loaded.first.isNew, isFalse);
      await again.read(menuDraftsProvider.notifier).remove('baru-1');
      expect((await again.read(menuDraftsProvider.future)).single.id, 'p1');
    },
  );

  test('saran harga channel memakai potongan per pcs', () async {
    await s.orders.saveChannel(
      s.businessId,
      name: 'Mitra',
      commissionPct: d('10'),
      feePerPcs: 500,
    );
    final rows = await PricingRepository(
      s.db,
      s.products,
    ).channelRows(s.brownies, s.businessId);
    final mitra = rows.firstWhere((r) => r.channel.name == 'Mitra');
    // (8.000 + 500) ÷ 0,9 = 9.444 → 9.500; potongan 800 + 500.
    expect(mitra.suggestion, 9500);
    expect(mitra.feePerPcs, d('1300'));
  });
}
