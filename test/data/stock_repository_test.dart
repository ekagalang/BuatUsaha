import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/data/db/app_database.dart';
import 'package:hpp_app/data/repositories/business_repository.dart';
import 'package:hpp_app/data/repositories/stock_repository.dart';

Decimal d(String value) => Decimal.parse(value);

DateTime oct(int day, [int hour = 9]) => DateTime.utc(2026, 10, day, hour);

void main() {
  late AppDatabase db;
  late StockRepository repo;
  late String businessId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = StockRepository(db);
    businessId = (await BusinessRepository(db).ensureDefault()).id;
  });
  tearDown(() => db.close());

  Future<IngredientView> view(String id) => repo.watchIngredient(id).first;

  Future<String> buy(
    String ingredientId, {
    required String qty,
    required int price,
    String unit = 'kg',
    String factor = '1000',
    DateTime? at,
  }) => repo.recordPurchase(
    businessId,
    PurchaseInput(
      purchasedAt: at ?? oct(19),
      lines: [
        PurchaseLineInput(
          ingredientId: ingredientId,
          qty: d(qty),
          unitName: unit,
          factorToBase: d(factor),
          totalPrice: price,
        ),
      ],
    ),
  );

  Future<Ingredient> flour({String? openingQty, String? openingCost}) =>
      repo.createIngredient(
        businessId: businessId,
        name: 'Tepung terigu',
        baseUnit: BaseUnit.g,
        openingQty: openingQty == null ? null : d(openingQty),
        openingUnitCost: openingCost == null ? null : d(openingCost),
        at: oct(1),
      );

  test('usaha bawaan dibuat sekali', () async {
    final again = await BusinessRepository(db).ensureDefault();
    expect(again.id, businessId);
  });

  group('Belanja dan harga rata-rata tertimbang', () {
    test('stok 0, beli 1 kg Rp14.000 → 1.000 g @ Rp14/g', () async {
      final tepung = await flour();
      await buy(tepung.id, qty: '1', price: 14000);

      final v = await view(tepung.id);
      expect(v.stock, d('1000'));
      expect(v.avgUnitCost, d('14'));
      expect(v.value, 14000);
    });

    test('500 g @ Rp14 + beli 1 kg Rp16.000 → 1.500 g @ Rp15,33/g', () async {
      final tepung = await flour(openingQty: '500', openingCost: '14');
      await buy(tepung.id, qty: '1', price: 16000);

      final v = await view(tepung.id);
      expect(v.stock, d('1500'));
      expect(v.avgUnitCost!.round(scale: 2), d('15.33'));
    });

    test('belanja tanpa item ditolak', () async {
      expect(
        () => repo.recordPurchase(
          businessId,
          PurchaseInput(purchasedAt: oct(19), lines: const []),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Stok awal dan harga perkiraan', () {
    test('cokelat stok awal 300 g @ Rp90 → nilai Rp27.000', () async {
      final cokelat = await repo.createIngredient(
        businessId: businessId,
        name: 'Cokelat batang',
        baseUnit: BaseUnit.g,
        openingQty: d('300'),
        openingUnitCost: d('90'),
      );

      final v = await view(cokelat.id);
      expect(v.stock, d('300'));
      expect(v.value, 27000);
      expect(cokelat.priceIsEstimate, isFalse);
    });

    test('harga perkiraan diganti belanja pertama 1 rak Rp63.000', () async {
      final telur = await repo.createIngredient(
        businessId: businessId,
        name: 'Telur',
        baseUnit: BaseUnit.pcs,
        estimatedUnitCost: d('2000'),
      );
      expect(telur.avgUnitCost, 2000);
      expect(telur.priceIsEstimate, isTrue);
      expect(telur.currentStock, 0);

      await repo.addCustomUnit(
        telur.id,
        unitName: 'rak',
        factorToBase: d('30'),
      );
      final units = await repo.unitOptions(telur.id);
      expect(units.map((u) => u.name), containsAll(['pcs', 'lusin', 'rak']));

      await buy(telur.id, qty: '1', price: 63000, unit: 'rak', factor: '30');
      final v = await view(telur.id);
      expect(v.avgUnitCost, d('2100'));
      expect(v.ingredient.priceIsEstimate, isFalse);
      expect(v.stock, d('30'));
    });

    test('bahan baru tanpa harga → harga kosong', () async {
      final santan = await repo.createIngredient(
        businessId: businessId,
        name: 'Santan',
        baseUnit: BaseUnit.ml,
      );
      expect(santan.avgUnitCost, isNull);
      expect((await view(santan.id)).value, 0);
    });

    test('stok awal ditolak setelah ada belanja', () async {
      final tepung = await flour();
      await buy(tepung.id, qty: '1', price: 14000);

      expect(
        () =>
            repo.recordOpening(tepung.id, qtyBase: d('100'), unitCost: d('14')),
        throwsStateError,
      );
    });
  });

  group('Koreksi transaksi', () {
    test('belanja salah ketik dibatalkan → harga kembali Rp14/g', () async {
      final tepung = await flour();
      await buy(tepung.id, qty: '1', price: 14000, at: oct(10));
      final typo = await buy(tepung.id, qty: '1', price: 140000, at: oct(11));
      expect((await view(tepung.id)).avgUnitCost, d('77'));

      await repo.voidPurchase(typo, reason: 'Salah ketik');

      final v = await view(tepung.id);
      expect(v.stock, d('1000'));
      expect(v.avgUnitCost, d('14'));

      final card = await repo.watchStockCard(tepung.id).first;
      expect(card, hasLength(3));
      expect(card.where((e) => e.cancelled), hasLength(1));
      expect(
        card.where((e) => e.isReversal).single.movement.note,
        'Salah ketik',
      );
    });

    test('edit belanja = batalkan + catat ulang', () async {
      final tepung = await flour();
      await buy(tepung.id, qty: '1', price: 14000, at: oct(10));
      final typo = await buy(tepung.id, qty: '1', price: 140000, at: oct(11));

      final fixedId = await repo.replacePurchase(
        typo,
        PurchaseInput(
          purchasedAt: oct(11),
          lines: [
            PurchaseLineInput(
              ingredientId: tepung.id,
              qty: d('1'),
              unitName: 'kg',
              factorToBase: d('1000'),
              totalPrice: 14000,
            ),
          ],
        ),
      );

      expect(fixedId, isNot(typo));
      final v = await view(tepung.id);
      expect(v.stock, d('2000'));
      expect(v.avgUnitCost, d('14'));
      final old = await (db.select(
        db.purchases,
      )..where((t) => t.id.equals(typo))).getSingle();
      expect(old.voidedAt, isNotNull);
      expect(() => repo.voidPurchase(typo, reason: 'lagi'), throwsStateError);
    });

    test(
      'belanja bertanggal mundur menghitung ulang nilai bahan rusak',
      () async {
        final tepung = await flour();
        await buy(tepung.id, qty: '1', price: 14000, at: oct(10));
        await repo.recordWaste(tepung.id, qtyBase: d('200'), at: oct(12));
        var card = await repo.watchStockCard(tepung.id).first;
        expect(card.first.movement.value, -2800);

        // Belanja tanggal 11 baru dicatat sekarang.
        await buy(tepung.id, qty: '1', price: 16000, at: oct(11));

        card = await repo.watchStockCard(tepung.id).first;
        final waste = card.firstWhere(
          (e) => e.movement.type == MovementType.waste,
        );
        expect(waste.movement.value, -3000);
        expect(waste.movement.balanceAfter, 1800);
        final v = await view(tepung.id);
        expect(v.stock, d('1800'));
        expect(v.avgUnitCost, d('15'));
      },
    );

    test('mutasi belanja tidak bisa dibatalkan langsung', () async {
      final tepung = await flour();
      await buy(tepung.id, qty: '1', price: 14000);
      final card = await repo.watchStockCard(tepung.id).first;

      expect(
        () => repo.voidMovement(card.single.movement.id, reason: 'x'),
        throwsStateError,
      );
    });

    test('penyesuaian yang dibatalkan tidak lagi memengaruhi stok', () async {
      final tepung = await flour(openingQty: '1000', openingCost: '14');
      await repo.recordAdjustment(tepung.id, qtyBase: d('-100'));
      expect((await view(tepung.id)).stock, d('900'));

      final card = await repo.watchStockCard(tepung.id).first;
      await repo.voidMovement(card.first.movement.id, reason: 'Salah hitung');
      expect((await view(tepung.id)).stock, d('1000'));
    });
  });

  group('Opname dan stok minimum', () {
    test('stok fisik 950 g dari buku 1.000 g → selisih −50 g', () async {
      final tepung = await flour(openingQty: '1000', openingCost: '14');

      final delta = await repo.recordOpname(
        tepung.id,
        countedQty: d('950'),
        at: oct(19),
      );

      expect(delta, d('-50'));
      final v = await view(tepung.id);
      expect(v.stock, d('950'));
      expect(v.value, 13300);
    });

    test(
      'di bawah minimum ditandai, lalu normal lagi setelah belanja',
      () async {
        final cokelat = await repo.createIngredient(
          businessId: businessId,
          name: 'Cokelat batang',
          baseUnit: BaseUnit.g,
          minStock: d('400'),
          openingQty: d('300'),
          openingUnitCost: d('90'),
        );
        expect((await view(cokelat.id)).isLow, isTrue);

        await (db.update(db.ingredients)..where((t) => t.id.equals(cokelat.id)))
            .write(const IngredientsCompanion(lowStockNotified: Value(true)));
        await buy(cokelat.id, qty: '1', price: 90000);

        final v = await view(cokelat.id);
        expect(v.isLow, isFalse);
        expect(v.ingredient.lowStockNotified, isFalse);
      },
    );
  });

  test('nilai modal sisa bahan contoh PRD = Rp255.000', () async {
    final stok = {
      'Tepung terigu': ('1000', '14', BaseUnit.g),
      'Gula pasir': ('500', '16', BaseUnit.g),
      'Telur': ('10', '2000', BaseUnit.pcs),
      'Cokelat batang': ('300', '90', BaseUnit.g),
      'Mentega': ('600', '60', BaseUnit.g),
      'Box kemasan': ('100', '1500', BaseUnit.pcs),
    };
    for (final MapEntry(key: name, value: (qty, cost, unit)) in stok.entries) {
      await repo.createIngredient(
        businessId: businessId,
        name: name,
        baseUnit: unit,
        openingQty: d(qty),
        openingUnitCost: d(cost),
      );
    }

    final all = await repo.watchIngredients(businessId).first;
    expect(all.map((v) => v.ingredient.name).first, 'Box kemasan');
    expect(all.fold(0, (sum, v) => sum + v.value), 255000);
  });
}
