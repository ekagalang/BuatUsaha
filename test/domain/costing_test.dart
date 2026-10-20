import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/domain/costing/costing.dart';
import 'package:buat_usaha/domain/enums.dart';

Decimal d(String value) => Decimal.parse(value);

/// Contoh brownies dari PRD bagian 6: 1 resep = 20 pcs.
final yieldQty = d('20');

List<RecipeLine> browniesRecipe({String cocoaUnitCost = '90'}) => [
  RecipeLine(ingredientId: 'tepung', qtyPerBatch: d('250'), unitCost: d('14')),
  RecipeLine(ingredientId: 'gula', qtyPerBatch: d('200'), unitCost: d('16')),
  RecipeLine(ingredientId: 'telur', qtyPerBatch: d('4'), unitCost: d('2000')),
  RecipeLine(
    ingredientId: 'cokelat',
    qtyPerBatch: d('200'),
    unitCost: d(cocoaUnitCost),
  ),
  RecipeLine(ingredientId: 'mentega', qtyPerBatch: d('150'), unitCost: d('60')),
  RecipeLine(ingredientId: 'box', qtyPerBatch: d('20'), unitCost: d('1500')),
];

const otherCosts = [
  OtherCost(name: 'Gas & listrik', amount: 5000, basis: CostBasis.perBatch),
  OtherCost(name: 'Tenaga kerja', amount: 20000, basis: CostBasis.perBatch),
];

final stock = {
  'tepung': d('1000'),
  'gula': d('500'),
  'telur': d('10'),
  'cokelat': d('300'),
  'mentega': d('600'),
  'box': d('100'),
};

void main() {
  group('Harga rata-rata tertimbang', () {
    test('belanja pertama: 1 kg Rp14.000 → 1.000 g @ Rp14/g', () {
      final qtyBase = toBaseQty(d('1'), d('1000'));
      final level = applyPurchase(
        StockLevel.empty,
        qtyBase: qtyBase,
        totalPrice: 14000,
      );

      expect(level.qty, d('1000'));
      expect(level.avgUnitCost, d('14'));
    });

    test('500 g @ Rp14 + beli 1 kg Rp16.000 → 1.500 g @ Rp15,33/g', () {
      final level = applyPurchase(
        StockLevel(qty: d('500'), avgUnitCost: d('14')),
        qtyBase: d('1000'),
        totalPrice: 16000,
      );

      expect(level.qty, d('1500'));
      expect(level.avgUnitCost.round(scale: 2), d('15.33'));
    });

    test('stok minus: harga baru = harga belanja', () {
      final level = applyPurchase(
        StockLevel(qty: d('-50'), avgUnitCost: d('14')),
        qtyBase: d('1000'),
        totalPrice: 16000,
      );

      expect(level.qty, d('950'));
      expect(level.avgUnitCost, d('16'));
    });

    test('stok keluar tidak mengubah harga rata-rata', () {
      final level = applyIssue(
        StockLevel(qty: d('1500'), avgUnitCost: d('15.333333')),
        qtyBase: d('250'),
      );

      expect(level.qty, d('1250'));
      expect(level.avgUnitCost, d('15.333333'));
    });
  });

  group('HPP brownies', () {
    test('biaya bahan Rp71.700, HPP Rp4.835/pcs', () {
      final hpp = calculateHpp(
        lines: browniesRecipe(),
        otherCosts: otherCosts,
        yieldQty: yieldQty,
      );

      expect(hpp.materialCostPerBatch, d('71700'));
      expect(hpp.otherCostPerBatch, d('25000'));
      expect(hpp.totalCostPerBatch, d('96700'));
      expect(hpp.hppPerPcs, d('4835'));
    });

    test('cokelat naik ke Rp100/g → HPP Rp4.935/pcs', () {
      final hpp = calculateHpp(
        lines: browniesRecipe(cocoaUnitCost: '100'),
        otherCosts: otherCosts,
        yieldQty: yieldQty,
      );

      expect(hpp.hppPerPcs, d('4935'));
    });

    test('biaya per pcs ditambahkan setelah dibagi hasil', () {
      final hpp = calculateHpp(
        lines: browniesRecipe(),
        otherCosts: [
          ...otherCosts,
          const OtherCost(name: 'Stiker', amount: 200, basis: CostBasis.perPcs),
        ],
        yieldQty: yieldQty,
      );

      expect(hpp.hppPerPcs, d('5035'));
    });
  });

  group('Saran harga jual', () {
    test('markup 60%, pembulatan Rp500 → Rp8.000', () {
      expect(
        suggestPriceByMarkup(hppPerPcs: d('4835'), markupPct: d('60')),
        8000,
      );
    });

    test('margin 40%, pembulatan Rp500 → Rp8.500', () {
      expect(
        suggestPriceByMargin(hppPerPcs: d('4835'), marginPct: d('40')),
        8500,
      );
    });

    test('margin aktual harga Rp8.000 = 39,56%', () {
      expect(
        actualMarginPct(sellingPrice: 8000, hppPerPcs: d('4835')),
        d('39.56'),
      );
    });

    test('pembulatan yang sudah pas tidak dinaikkan', () {
      expect(ceilToStep(d('8000'), 500), 8000);
      expect(ceilToStep(d('8000.01'), 500), 8500);
    });
  });

  group('Kapasitas produksi', () {
    test('stok saat ini cukup untuk 30 pcs, pembatas cokelat', () {
      final result = calculateCapacity(
        lines: browniesRecipe(),
        stock: stock,
        yieldQty: yieldQty,
      );

      expect(result.maxBatches, d('1.5'));
      expect(result.maxPcs, 30);
      expect(result.limitingIngredientIds, ['cokelat']);
    });

    test('resep tidak bisa dipecah → 1 resep = 20 pcs', () {
      final result = calculateCapacity(
        lines: browniesRecipe(),
        stock: stock,
        yieldQty: yieldQty,
        wholeBatchesOnly: true,
      );

      expect(result.maxPcs, 20);
    });

    test('bahan tanpa stok membuat kapasitas 0', () {
      final result = calculateCapacity(
        lines: browniesRecipe(),
        stock: {...stock}..remove('box'),
        yieldQty: yieldQty,
      );

      expect(result.maxPcs, 0);
      expect(result.limitingIngredientIds, ['box']);
    });

    test(
      'target 60 pcs: kurang cokelat 300 g, gula 100 g, telur 2 → Rp32.600',
      () {
        final shortages = calculateShortages(
          lines: browniesRecipe(),
          stock: stock,
          yieldQty: yieldQty,
          targetPcs: 60,
        );

        final missing = {
          for (final s in shortages) s.ingredientId: s.missingQty,
        };
        expect(missing, {
          'gula': d('100'),
          'telur': d('2'),
          'cokelat': d('300'),
        });
        expect(estimateShoppingCost(shortages), 32600);
      },
    );
  });

  group('Nilai modal sisa bahan', () {
    test('total Rp255.000', () {
      final lines = [
        for (final line in browniesRecipe())
          StockValueLine(
            ingredientId: line.ingredientId,
            qty: stock[line.ingredientId]!,
            avgUnitCost: line.unitCost,
          ),
      ];

      expect(totalStockValue(lines), 255000);
    });

    test('stok minus tidak dihitung', () {
      expect(
        totalStockValue([
          StockValueLine(
            ingredientId: 'a',
            qty: d('-10'),
            avgUnitCost: d('100'),
          ),
          StockValueLine(ingredientId: 'b', qty: d('3'), avgUnitCost: d('100')),
          StockValueLine(
            ingredientId: 'santan',
            qty: d('400'),
            avgUnitCost: null,
          ),
        ]),
        300,
      );
    });

    test('stok menu jadi: 6 toples cookies @ Rp18.000 = Rp108.000', () {
      expect(
        totalStockValue([
          StockValueLine(
            ingredientId: 'cookies',
            qty: d('6'),
            avgUnitCost: d('18000'),
          ),
        ]),
        108000,
      );
    });
  });

  group('Status HPP dan upah pemilik', () {
    test('upah pemilik 2 jam × Rp10.000 = Rp20.000 per resep', () {
      expect(laborCost(hours: d('2'), hourlyWage: 10000), 20000);
      expect(laborCost(hours: d('1.5'), hourlyWage: 12500), 18750);
    });

    test('resep lengkap → status COMPLETE', () {
      final hpp = calculateHpp(
        lines: browniesRecipe(),
        otherCosts: otherCosts,
        yieldQty: yieldQty,
      );

      expect(hpp.status, HppStatus.complete);
      expect(hpp.missingPriceIngredientIds, isEmpty);
    });

    test('bahan tanpa harga → INCOMPLETE dan bahannya disebut', () {
      final hpp = calculateHpp(
        lines: [
          ...browniesRecipe(),
          RecipeLine(
            ingredientId: 'almond',
            qtyPerBatch: d('50'),
            unitCost: null,
          ),
        ],
        otherCosts: otherCosts,
        yieldQty: yieldQty,
      );

      expect(hpp.status, HppStatus.incomplete);
      expect(hpp.missingPriceIngredientIds, ['almond']);
      expect(hpp.hppPerPcs, d('4835'));
    });

    test('harga perkiraan → ESTIMATED dan ikut dihitung', () {
      final hpp = calculateHpp(
        lines: [
          ...browniesRecipe(),
          RecipeLine(
            ingredientId: 'almond',
            qtyPerBatch: d('50'),
            unitCost: d('180'),
            isEstimate: true,
          ),
        ],
        otherCosts: otherCosts,
        yieldQty: yieldQty,
      );

      expect(hpp.status, HppStatus.estimated);
      expect(hpp.hppPerPcs, d('5285'));
    });

    test('kekurangan bahan tanpa harga tidak ikut perkiraan belanja', () {
      final shortages = calculateShortages(
        lines: [
          RecipeLine(
            ingredientId: 'santan',
            qtyPerBatch: d('200'),
            unitCost: null,
          ),
          RecipeLine(
            ingredientId: 'gula',
            qtyPerBatch: d('100'),
            unitCost: d('16'),
          ),
        ],
        stock: {},
        yieldQty: d('10'),
        targetPcs: 10,
      );

      expect(shortages.first.estimatedCost, isNull);
      expect(estimateShoppingCost(shortages), 1600);
    });
  });

  group('Stok produk jadi dan hitung ulang buku mutasi', () {
    test('produksi masuk stok dengan HPP rata-rata tertimbang', () {
      final level = applyReceipt(
        StockLevel(qty: d('6'), avgUnitCost: d('18000')),
        qty: d('10'),
        unitCost: d('17000'),
      );

      expect(level.qty, d('16'));
      expect(level.avgUnitCost, d('17375'));
    });

    test(
      'koreksi belanja salah ketik: Rp140.000 → Rp14.000 dihitung ulang',
      () {
        List<StockLevel> replay(int purchasePrice) => replayLedger([
          LedgerEntry.receipt(qty: d('500'), totalValue: d('7000')),
          LedgerEntry.receipt(
            qty: d('1000'),
            totalValue: rupiah(purchasePrice),
          ),
          LedgerEntry.issue(qty: d('250')),
        ]);

        final typo = replay(140000);
        expect(typo.last.avgUnitCost, d('98'));

        final fixed = replay(14000);
        expect(fixed.map((l) => l.qty), [d('500'), d('1500'), d('1250')]);
        expect(fixed.last.avgUnitCost, d('14'));
      },
    );
  });

  group('Channel penjualan', () {
    test('GoFood 20% dari Rp80.000 = Rp16.000', () {
      expect(channelFee(itemsTotal: 80000, commissionPct: d('20')), 16000);
    });

    test('komisi + biaya tetap per transaksi', () {
      expect(
        channelFee(
          itemsTotal: 50000,
          commissionPct: d('2.5'),
          feePerOrder: 1000,
        ),
        2250,
      );
    });

    test('potongan dibagi ke item sesuai porsi, jumlahnya tetap', () {
      final shares = allocateProportionally(1000, [200, 100, 100]);

      expect(shares, [500, 250, 250]);
      final odd = allocateProportionally(100, [1, 1, 1]);
      expect(odd.fold(0, (a, b) => a + b), 100);
    });

    test('10 brownies lewat GoFood 20% → laba Rp15.650', () {
      final fee = channelFee(itemsTotal: 80000, commissionPct: d('20'));
      final line = ProductDayLine(
        productId: 'brownies',
        revenue: 80000,
        channelFee: fee,
        cogs: d('48350'),
      );

      expect(toRupiah(line.profit), 15650);
    });
  });

  group('Ringkasan harian (contoh PRD bagian 6)', () {
    final summary = summarizeDay(
      lines: [
        ProductDayLine(
          productId: 'brownies',
          revenue: 200000,
          cogs: d('120875'),
          wasteLoss: d('24175'),
        ),
        ProductDayLine(productId: 'cookies', revenue: 120000, cogs: d('72000')),
      ],
      expenses: 20000,
    );

    test('laba menu Rp102.950, laba bersih Rp82.950, Untung', () {
      expect(summary.revenue, 320000);
      expect(summary.cogs, 192875);
      expect(summary.wasteLoss, 24175);
      expect(summary.menuProfit, 102950);
      expect(summary.netProfit, 82950);
      expect(summary.status, DayStatus.profit);
    });

    test('laba per menu dan menu yang paling menekan laba', () {
      expect(toRupiah(summary.lines[0].profit), 54950);
      expect(toRupiah(summary.lines[1].profit), 48000);
      expect(summary.mostPressuringProductId, 'brownies');
    });

    test('jika 5 brownies disimpan, laba menu menjadi Rp127.125', () {
      final kept = summarizeDay(
        lines: [
          ProductDayLine(
            productId: 'brownies',
            revenue: 200000,
            cogs: d('120875'),
          ),
          ProductDayLine(
            productId: 'cookies',
            revenue: 120000,
            cogs: d('72000'),
          ),
        ],
      );

      expect(kept.menuProfit, 127125);
    });

    test('pengeluaran lebih besar dari laba → Rugi', () {
      final loss = summarizeDay(
        lines: [
          ProductDayLine(
            productId: 'cookies',
            revenue: 30000,
            cogs: d('18000'),
          ),
        ],
        expenses: 20000,
      );

      expect(loss.netProfit, -8000);
      expect(loss.status, DayStatus.loss);
    });
  });

  group('Umur simpan', () {
    final day = DateTime.utc;

    test('brownies 19 Okt umur 3 hari aman s.d. 21 Okt', () {
      expect(lastGoodDay(day(2026, 10, 19), 3), day(2026, 10, 21));
    });

    test('diproduksi tgl 1: tgl 3 habis besok, tgl 4 lewat umur simpan', () {
      ShelfStatus on(int date) => shelfStatus(
        producedOn: day(2026, 10, 1),
        shelfLifeDays: 3,
        today: day(2026, 10, date),
      );

      expect(on(2), ShelfStatus.fresh);
      expect(on(3), ShelfStatus.expiresTomorrow);
      expect(on(4), ShelfStatus.expired);
    });

    test('sisa stok dianggap dari batch terbaru', () {
      final batches = remainingBatches(
        productions: [
          ProductionBatch(producedOn: day(2026, 10, 1), qty: d('30')),
          ProductionBatch(producedOn: day(2026, 10, 3), qty: d('20')),
        ],
        currentStock: d('25'),
      );

      expect(batches.map((b) => b.producedOn), [
        day(2026, 10, 3),
        day(2026, 10, 1),
      ]);
      expect(batches.map((b) => b.qty), [d('20'), d('5')]);
    });
  });
}
