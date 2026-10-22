import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/business_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> namesOf(String type) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
          variables: [Variable.withString(type)],
        )
        .get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  test('membuat 21 tabel MVP + 2 tabel sinkron + 2 tabel belanja + 4 tabel harga dan kas', () async {
    expect(
      await namesOf('table'),
      unorderedEquals([
        'businesses',
        'notification_settings',
        'ingredients',
        'ingredient_units',
        'suppliers',
        'purchases',
        'purchase_items',
        'stock_movements',
        'products',
        'recipe_items',
        'product_costs',
        'productions',
        'product_stock_movements',
        'customers',
        'sales_channels',
        'orders',
        'order_items',
        'payments',
        'order_reminders',
        'expense_categories',
        'expenses',
        'sync_outbox',
        'sync_state',
        'shopping_lists',
        'shopping_list_items',
        'product_channel_prices',
        'product_hpp_history',
        'cash_accounts',
        'cash_entries',
      ]),
    );
  });

  test('membuat indeks yang disarankan', () async {
    expect(
      await namesOf('index'),
      containsAll([
        'orders_business_due',
        'orders_business_status',
        'orders_business_completed',
        'stock_movements_ingredient_time',
        'product_stock_movements_product_time',
        'order_reminders_status_time',
        'expenses_business_spent',
      ]),
    );
  });

  test('id UUID dan enum tersimpan sebagai kode TEXT', () async {
    final business = await db
        .into(db.businesses)
        .insertReturning(BusinessesCompanion.insert(name: 'Dapur Rina'));
    final ingredient = await db
        .into(db.ingredients)
        .insertReturning(
          IngredientsCompanion.insert(
            businessId: business.id,
            name: 'Cokelat batang',
            baseUnit: BaseUnit.g,
          ),
        );

    expect(business.id, hasLength(36));
    expect(business.stockDeductMode, StockDeductMode.onProduction);
    expect(ingredient.category, IngredientCategory.raw);
    expect(ingredient.baseUnit, BaseUnit.g);
    expect(ingredient.avgUnitCost, isNull);
    expect(ingredient.priceIsEstimate, isFalse);

    final raw = await db
        .customSelect('SELECT category, base_unit FROM ingredients')
        .getSingle();
    expect(raw.read<String>('category'), 'RAW');
    expect(raw.read<String>('base_unit'), 'g');
  });

  test('foreign key ditegakkan', () async {
    await expectLater(
      db
          .into(db.ingredients)
          .insert(
            IngredientsCompanion.insert(
              businessId: 'tidak-ada',
              name: 'Tepung',
              baseUnit: BaseUnit.g,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('resep unik per pasangan produk dan bahan', () async {
    final business = await db
        .into(db.businesses)
        .insertReturning(BusinessesCompanion.insert(name: 'Dapur Rina'));
    final flour = await db
        .into(db.ingredients)
        .insertReturning(
          IngredientsCompanion.insert(
            businessId: business.id,
            name: 'Tepung',
            baseUnit: BaseUnit.g,
          ),
        );
    final product = await db
        .into(db.products)
        .insertReturning(
          ProductsCompanion.insert(
            businessId: business.id,
            name: 'Brownies',
            sellingPrice: 8000,
            yieldQty: 20,
          ),
        );
    final line = RecipeItemsCompanion.insert(
      productId: product.id,
      ingredientId: flour.id,
      qtyBase: 250,
    );

    // id dibuat ulang (clientDefault) di tiap insert, jadi yang bentrok
    // hanya pasangan product_id + ingredient_id.
    await db.into(db.recipeItems).insert(line);
    await expectLater(
      db.into(db.recipeItems).insert(line),
      throwsA(isA<SqliteException>()),
    );
  });

  test('menu baru: HPP belum lengkap, stok 0, ikut mode stok usaha', () async {
    final business = await db
        .into(db.businesses)
        .insertReturning(BusinessesCompanion.insert(name: 'Dapur Rina'));
    final product = await db
        .into(db.products)
        .insertReturning(
          ProductsCompanion.insert(
            businessId: business.id,
            name: 'Brownies',
            sellingPrice: 8000,
            yieldQty: 20,
            shelfLifeDays: const Value(3),
          ),
        );

    expect(product.hppStatus, HppStatus.incomplete);
    expect(product.stockDeductMode, isNull);
    expect(product.currentStock, 0);
    expect(product.shelfLifeDays, 3);

    final movement = await db
        .into(db.productStockMovements)
        .insertReturning(
          ProductStockMovementsCompanion.insert(
            productId: product.id,
            type: ProductMovementType.waste,
            qty: -5,
            unitCost: 4835,
            value: -24175,
            balanceAfter: 0,
            avgCostAfter: 4835,
            reason: const Value(WasteReason.damaged),
            occurredAt: DateTime.utc(2026, 10, 19, 13),
          ),
        );
    expect(movement.reason, WasteReason.damaged);

    final raw = await db
        .customSelect('SELECT type, reason FROM product_stock_movements')
        .getSingle();
    expect(raw.read<String>('type'), 'WASTE');
    expect(raw.read<String>('reason'), 'DAMAGED');
  });

  test('pesanan menyimpan channel, potongan, dan bisa dibatalkan', () async {
    final business = await db
        .into(db.businesses)
        .insertReturning(BusinessesCompanion.insert(name: 'Dapur Rina'));
    final gofood = await db
        .into(db.salesChannels)
        .insertReturning(
          SalesChannelsCompanion.insert(
            businessId: business.id,
            name: 'GoFood',
            commissionPct: const Value(20),
          ),
        );
    final order = await db
        .into(db.orders)
        .insertReturning(
          OrdersCompanion.insert(
            businessId: business.id,
            orderNo: 'PO-261020-001',
            channelId: Value(gofood.id),
            type: OrderType.direct,
            dueAt: DateTime.utc(2026, 10, 20, 5),
            subtotal: 80000,
            total: 80000,
            channelFee: const Value(16000),
          ),
        );

    expect(order.channelId, gofood.id);
    expect(order.channelFee, 16000);
    expect(order.voidedAt, isNull);

    await (db.update(db.orders)..where((o) => o.id.equals(order.id))).write(
      OrdersCompanion(
        voidedAt: Value(DateTime.utc(2026, 10, 20, 9)),
        voidReason: const Value('Salah input'),
      ),
    );
    final voided = await (db.select(
      db.orders,
    )..where((o) => o.id.equals(order.id))).getSingle();
    expect(voided.voidReason, 'Salah input');
  });

  test(
    'migrasi skema v1 ke v7 menambah kolom dan tabel tanpa menghapus data',
    () async {
      final dir = Directory.systemTemp.createTempSync('hpp_migrasi');
      final file = File('${dir.path}/app.sqlite');
      var old = AppDatabase(NativeDatabase(file));
      final id = (await BusinessRepository(old).ensureDefault()).id;
      // Trigger sinkron (TEMP) menunjuk kolom dan tabel yang akan dibuang
      // untuk meniru skema v1.
      final triggers = await old
          .customSelect(
            "SELECT name FROM sqlite_temp_master WHERE type = 'trigger'",
          )
          .get();
      for (final t in triggers) {
        await old.customStatement(
          'DROP TRIGGER temp.${t.read<String>('name')}',
        );
      }
      await old.customStatement(
        'ALTER TABLE businesses DROP COLUMN onboarded_at',
      );
      await old.customStatement('ALTER TABLE expenses DROP COLUMN is_monthly');
      await old.customStatement('ALTER TABLE businesses DROP COLUMN owner_uid');
      await old.customStatement('DROP TABLE sync_outbox');
      await old.customStatement('DROP TABLE sync_state');
      await old.customStatement(
        'ALTER TABLE products DROP COLUMN safety_stock',
      );
      await old.customStatement('DROP TABLE shopping_list_items');
      await old.customStatement('DROP TABLE shopping_lists');
      for (final c in [
        'address',
        'payment_info',
        'receipt_note',
        'logo_data',
        'receipt_size',
      ]) {
        await old.customStatement('ALTER TABLE businesses DROP COLUMN $c');
      }
      for (final t in [
        'cash_entries',
        'cash_accounts',
        'product_hpp_history',
        'product_channel_prices',
      ]) {
        await old.customStatement('DROP TABLE $t');
      }
      for (final t in ['payments', 'purchases', 'expenses']) {
        await old.customStatement('ALTER TABLE $t DROP COLUMN cash_account_id');
      }
      for (final (t, c) in [
        ('ingredients', 'count_unit'),
        ('ingredients', 'archived_at'),
        ('products', 'archived_at'),
        ('recipe_items', 'unit_name'),
        ('recipe_items', 'unit_factor'),
        ('sales_channels', 'fee_per_pcs'),
        ('ingredient_units', 'hidden'),
        ('ingredient_units', 'for_recipe'),
      ]) {
        await old.customStatement('ALTER TABLE $t DROP COLUMN $c');
      }
      await old.customStatement('PRAGMA user_version = 1');
      await old.close();

      old = AppDatabase(NativeDatabase(file));
      final business = await old.select(old.businesses).getSingle();
      expect(business.id, id);
      expect(business.onboardedAt, isNull);
      expect(business.ownerUid, isNull);
      expect(business.receiptSize, ReceiptSize.a6);
      expect(business.paymentInfo, isNull);
      expect(await old.select(old.syncOutbox).get(), isEmpty);
      expect(await old.select(old.shoppingLists).get(), isEmpty);
      // Akun kas bawaan dibuat lagi saat usaha dibuka.
      await BusinessRepository(old).ensureDefault();
      expect(await old.select(old.cashAccounts).get(), hasLength(3));
      // Perbaikan stok awal data lama menunggu dijalankan sekali (FR-20.6).
      expect(
        (await old.select(old.syncState).get()).map((s) => s.entity),
        contains(AppDatabase.openingFixKey),
      );
      final columns = await old
          .customSelect("SELECT name FROM pragma_table_info('expenses')")
          .get();
      expect(
        columns.map((r) => r.read<String>('name')),
        contains('is_monthly'),
      );
      await old.close();
      dir.deleteSync(recursive: true);
    },
  );
}
