import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/business_repository.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';
import 'package:buat_usaha/data/repositories/product_repository.dart';
import 'package:buat_usaha/data/repositories/stock_repository.dart';
import 'package:buat_usaha/data/sync/remote_store.dart';
import 'package:buat_usaha/data/sync/sync_engine.dart';

import '../support/fake_remote_store.dart';
import '../support/seed.dart';

const uid = 'akun-rina';

/// Satu HP: database sendiri, server yang sama.
class Phone {
  Phone(this.db, RemoteStore remote)
    : engine = SyncEngine(db, remote),
      business = BusinessRepository(db),
      stock = StockRepository(db) {
    products = ProductRepository(db, stock);
    orders = OrderRepository(db, stock, products);
  }

  final AppDatabase db;
  final SyncEngine engine;
  final BusinessRepository business;
  final StockRepository stock;
  late final ProductRepository products;
  late final OrderRepository orders;

  /// HP baru: aplikasi baru dipasang, usaha bawaan dibuat otomatis.
  static Future<Phone> fresh(RemoteStore remote) async {
    final phone = Phone(AppDatabase(NativeDatabase.memory()), remote);
    await phone.business.ensureDefault();
    return phone;
  }

  /// HP berisi data contoh PRD (bahan brownies dan menunya).
  static Future<(Phone, Seed)> seeded(RemoteStore remote) async {
    final seed = await Seed.create();
    return (Phone(seed.db, remote), seed);
  }

  Future<Business> theBusiness() => db.select(db.businesses).getSingle();

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<List<String>> ids(String table) async => [
    for (final r
        in await db.customSelect('SELECT id FROM $table ORDER BY id').get())
      r.read<String>('id'),
  ];

  Future<Ingredient> ingredient(String id) =>
      (db.select(db.ingredients)..where((t) => t.id.equals(id))).getSingle();

  Future<Product> product(String id) =>
      (db.select(db.products)..where((t) => t.id.equals(id))).getSingle();

  Future<List<Order>> allOrders() =>
      (db.select(db.orders)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Login pertama tanpa dialog (akun kosong atau HP kosong).
  Future<void> login() async {
    final check = await engine.check(uid);
    await engine.link(uid, check.plan);
  }

  Future<void> close() => db.close();
}

/// Perubahan di HP yang berbeda harus beda milidetik (versi `changed_at`).
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 15));

OrderInput twoBrownies(String productId) => OrderInput(
  dueAt: DateTime(2026, 12, 25, 10),
  items: [OrderItemInput(productId: productId, qty: 2, unitPrice: 8000)],
);

void main() {
  late FakeRemoteStore remote;
  final open = <Phone>[];

  setUp(() => remote = FakeRemoteStore());
  tearDown(() async {
    for (final p in open) {
      await p.close();
    }
    open.clear();
  });

  Future<(Phone, Seed)> seededPhone() async {
    final result = await Phone.seeded(remote);
    open.add(result.$1);
    return result;
  }

  Future<Phone> freshPhone() async {
    final phone = await Phone.fresh(remote);
    open.add(phone);
    return phone;
  }

  /// HP A berisi data lalu login; HP B baru dipasang lalu login.
  Future<(Phone, Phone, Seed)> twoLinkedPhones() async {
    final (a, seed) = await seededPhone();
    await a.login();
    final b = await freshPhone();
    await b.login();
    return (a, b, seed);
  }

  test('login pertama di HP berisi data mengunggah semuanya', () async {
    final (a, _) = await seededPhone();
    final check = await a.engine.check(uid);
    expect(check.plan, LinkPlan.upload);

    await a.engine.link(uid, check.plan);

    expect(remote.live(uid, 'ingredients'), hasLength(5));
    expect(remote.live(uid, 'recipe_items'), hasLength(5));
    expect(remote.live(uid, 'sales_channels'), hasLength(6));
    expect(await a.engine.pendingCount(), 0);
    expect(await a.engine.linkedUid(), uid);
    // uid hanya berlaku di HP ini, tidak ikut dikirim.
    expect(
      remote.live(uid, 'businesses').single.containsKey('owner_uid'),
      false,
    );
  });

  test('HP baru mengunduh data akun dan menghitung ulang cache', () async {
    final (a, seed) = await seededPhone();
    await a.login();
    final b = await freshPhone();

    final check = await b.engine.check(uid);
    expect(check.plan, LinkPlan.download);
    await b.engine.link(uid, check.plan);

    expect((await b.theBusiness()).id, seed.businessId);
    expect(await b.count('businesses'), 1);
    expect(await b.count('sales_channels'), 6);
    expect(await b.ids('ingredients'), await a.ids('ingredients'));
    final tepung = await b.ingredient(seed.ids['tepung']!);
    expect(tepung.currentStock, 1000);
    expect(tepung.avgUnitCost, 12);
    final brownies = await b.product(seed.brownies);
    expect(brownies.hppPerPcs, 4835);
    expect(brownies.hppStatus, HppStatus.complete);
    expect(await b.engine.pendingCount(), 0);
  });

  test('perubahan di satu HP sampai ke HP lain', () async {
    final (a, b, seed) = await twoLinkedPhones();
    await a.stock.recordPurchase(
      seed.businessId,
      PurchaseInput(
        purchasedAt: DateTime.utc(2026, 10, 5),
        lines: [
          PurchaseLineInput(
            ingredientId: seed.ids['tepung']!,
            qty: d('1'),
            unitName: 'kg',
            factorToBase: d('1000'),
            totalPrice: 14000,
          ),
        ],
      ),
    );
    expect(await a.engine.pendingCount(), greaterThan(0));
    await a.engine.sync(uid);
    await b.engine.sync(uid);

    final tepung = await b.ingredient(seed.ids['tepung']!);
    expect(tepung.currentStock, 2000);
    expect(tepung.avgUnitCost, 13);
    expect(
      (await b.product(seed.brownies)).hppPerPcs,
      (await a.product(seed.brownies)).hppPerPcs,
    );
    expect(await b.count('purchases'), 1);
    expect(await b.engine.pendingCount(), 0);
  });

  test('hitung ulang cache saja tidak memicu kiriman', () async {
    final (a, _, seed) = await twoLinkedPhones();
    await a.engine.sync(uid);
    expect(await a.engine.pendingCount(), 0);

    await a.stock.recomputeIngredient(seed.ids['tepung']!);
    await a.products.recordProduction(
      seed.brownies,
      batchQty: d('1'),
      at: DateTime.utc(2026, 10, 6),
    );
    final pending = await a.engine.pendingCount();
    await a.stock.recomputeIngredient(seed.ids['tepung']!);
    expect(await a.engine.pendingCount(), pending);
  });

  test('menarik lagi data sendiri tidak mengubah apa pun', () async {
    final (a, b, _) = await twoLinkedPhones();
    await a.engine.sync(uid);
    await b.engine.sync(uid);
    final writes = remote.writeCount;

    await a.engine.sync(uid);
    await b.engine.sync(uid);

    expect(remote.writeCount, writes);
    expect(await a.engine.pendingCount(), 0);
    expect(await b.engine.pendingCount(), 0);
  });

  test('perubahan terbaru menang (FR-10.4)', () async {
    final (a, b, seed) = await twoLinkedPhones();
    final tepung = seed.ids['tepung']!;
    await a.stock.updateIngredient(tepung, name: 'Tepung dari A');
    await tick();
    await b.stock.updateIngredient(tepung, name: 'Tepung dari B');

    // B mengirim dulu; A yang perubahannya lebih lama menarik sebelum kirim.
    await b.engine.sync(uid);
    await a.engine.sync(uid);
    await b.engine.sync(uid);

    expect((await a.ingredient(tepung)).name, 'Tepung dari B');
    expect((await b.ingredient(tepung)).name, 'Tepung dari B');
    expect(await a.engine.pendingCount(), 0);
  });

  test(
    'nomor pesanan yang bentrok diberi nomor baru, sama di kedua HP',
    () async {
      final (a, b, seed) = await twoLinkedPhones();
      await a.orders.createOrder(seed.businessId, twoBrownies(seed.brownies));
      await tick();
      await b.orders.createOrder(seed.businessId, twoBrownies(seed.brownies));

      await a.engine.sync(uid);
      await b.engine.sync(uid);
      await a.engine.sync(uid);
      await b.engine.sync(uid);

      final onA = await a.allOrders();
      final onB = await b.allOrders();
      expect(onA.map((o) => o.orderNo), ['PO-261225-001', 'PO-261225-002']);
      expect(
        onB.map((o) => (o.id, o.orderNo)),
        onA.map((o) => (o.id, o.orderNo)),
      );
      // Pengingat dari HP lain mendapat id notifikasi sendiri di HP ini.
      final reminders = await b.db.select(b.db.orderReminders).get();
      expect(reminders, hasLength(4));
      expect(reminders.map((r) => r.notificationId).toSet(), hasLength(4));
    },
  );

  test('menu yang diubah di dua HP tidak dobel resep dan biayanya', () async {
    final (a, b, seed) = await twoLinkedPhones();
    final edited = seed.browniesInput(name: 'Brownies fudge');
    await a.products.updateProduct(seed.brownies, edited);
    await tick();
    await b.products.updateProduct(seed.brownies, edited);

    await a.engine.sync(uid);
    await b.engine.sync(uid);
    await a.engine.sync(uid);

    for (final phone in [a, b]) {
      expect(await phone.count('recipe_items'), 5);
      expect(await phone.count('product_costs'), 3);
      expect((await phone.product(seed.brownies)).hppPerPcs, 4835);
    }
    expect(await b.ids('recipe_items'), await a.ids('recipe_items'));
  });

  test('bahan yang ditambah di dua HP ke resep yang sama hanya satu', () async {
    final (a, b, seed) = await twoLinkedPhones();
    final vanili = (await a.stock.createIngredient(
      businessId: seed.businessId,
      name: 'Vanili',
      baseUnit: BaseUnit.g,
    )).id;
    await a.engine.sync(uid);
    await b.engine.sync(uid);
    final withVanilla = seed.browniesInput();
    final input = ProductInput(
      name: withVanilla.name,
      sellingPrice: withVanilla.sellingPrice,
      yieldQty: withVanilla.yieldQty,
      shelfLifeDays: withVanilla.shelfLifeDays,
      recipe: [
        ...withVanilla.recipe,
        RecipeInput(ingredientId: vanili, qtyBase: d('5')),
      ],
      costs: withVanilla.costs,
    );
    await a.products.updateProduct(seed.brownies, input);
    await tick();
    await b.products.updateProduct(seed.brownies, input);

    await a.engine.sync(uid);
    await b.engine.sync(uid);
    await a.engine.sync(uid);

    expect(await a.count('recipe_items'), 6);
    expect(await b.ids('recipe_items'), await a.ids('recipe_items'));
    expect(remote.live(uid, 'recipe_items'), hasLength(6));
  });

  test('akun berisi data lain: digabung', () async {
    final (a, seedA) = await seededPhone();
    await a.orders.createOrder(seedA.businessId, twoBrownies(seedA.brownies));
    await a.login();
    final (c, seedC) = await seededPhone();
    await seedC.channel('Tokopedia', '5');
    await c.orders.createOrder(seedC.businessId, twoBrownies(seedC.brownies));

    final check = await c.engine.check(uid);
    expect(check.plan, LinkPlan.choose);
    expect(check.local.ingredients, 5);
    expect(check.local.products, 1);
    expect(check.local.orders, 1);
    expect(check.remoteUpdatedAt, isNotNull);
    await c.engine.link(uid, check.plan, choice: LinkChoice.merge);

    expect((await c.theBusiness()).id, seedA.businessId);
    expect(await c.count('ingredients'), 10);
    expect(await c.count('products'), 2);
    // Channel bawaan bernama sama dipakai bersama.
    expect(await c.count('sales_channels'), 7);
    expect(await c.count('expense_categories'), 6);
    expect(await c.count('notification_settings'), 1);
    expect((await c.allOrders()).map((o) => o.orderNo).toSet(), {
      'PO-261225-001',
      'PO-261225-002',
    });
    expect((await c.product(seedC.brownies)).hppPerPcs, 4835);
    expect(await c.engine.pendingCount(), 0);

    await a.engine.sync(uid);
    expect(await a.count('ingredients'), 10);
    expect(await a.count('products'), 2);
    expect(await a.count('sales_channels'), 7);
    expect(await a.count('orders'), 2);
    expect(await a.ids('orders'), await c.ids('orders'));
  });

  test('akun berisi data lain: data HP diganti data akun', () async {
    final (a, seedA) = await seededPhone();
    await a.login();
    final (c, _) = await seededPhone();

    final check = await c.engine.check(uid);
    await c.engine.link(uid, check.plan, choice: LinkChoice.replace);

    expect((await c.theBusiness()).id, seedA.businessId);
    expect(await c.ids('ingredients'), await a.ids('ingredients'));
    expect(await c.ids('products'), [seedA.brownies]);
    expect((await c.ingredient(seedA.ids['cokelat']!)).currentStock, 300);
  });

  test('keluar akun: data tetap di HP, lalu login lagi digabung', () async {
    final (a, seed) = await seededPhone();
    await a.login();
    await a.engine.unlink(wipe: false);

    expect(await a.engine.linkedUid(), isNull);
    await a.stock.updateIngredient(seed.ids['gula']!, name: 'Gula pasir');
    // Saat keluar akun perubahan tidak diantrekan.
    expect(await a.engine.pendingCount(), 0);

    final check = await a.engine.check(uid);
    expect(check.plan, LinkPlan.rejoin);
    await a.engine.link(uid, check.plan);

    expect(await a.count('ingredients'), 5);
    expect(
      remote.live(uid, 'ingredients').map((r) => r['name']),
      contains('Gula pasir'),
    );
    expect(await a.engine.pendingCount(), 0);
  });

  test('keluar akun dan hapus data dari HP', () async {
    final (a, _) = await seededPhone();
    await a.login();
    await a.engine.unlink(wipe: true);

    expect(await a.count('ingredients'), 0);
    expect(await a.count('businesses'), 0);
    expect(await a.engine.pendingCount(), 0);
    expect(remote.live(uid, 'ingredients'), hasLength(5));
  });

  test('tanpa internet perubahan menunggu lalu terkirim saat online', () async {
    final (a, b, seed) = await twoLinkedPhones();
    remote.offline = true;
    await a.stock.updateIngredient(seed.ids['telur']!, name: 'Telur ayam');
    expect(await a.engine.pendingCount(), 1);

    await expectLater(a.engine.sync(uid), throwsStateError);
    expect(await a.engine.pendingCount(), 1);

    remote.offline = false;
    await a.engine.sync(uid);
    await b.engine.sync(uid);
    expect(await a.engine.pendingCount(), 0);
    expect((await b.ingredient(seed.ids['telur']!)).name, 'Telur ayam');
  });
}
