import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'product_repository.dart';

const dayCloseRef = 'day_close';

/// `2026-10-20` dari tanggal lokal.
String dayKey(DateTime day) {
  final d = day.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

DateTime startOfDay(DateTime day) {
  final d = day.toLocal();
  return DateTime(d.year, d.month, d.day);
}

class LeftoverBatch {
  const LeftoverBatch({
    required this.producedOn,
    required this.qty,
    required this.status,
  });

  /// `null` = stok awal tanpa tanggal produksi.
  final DateTime? producedOn;
  final Decimal qty;
  final ShelfStatus status;
}

/// Sisa satu menu ready stock saat Tutup hari (FR-4.6, FR-4.10).
class Leftover {
  const Leftover({required this.product, required this.batches});

  final Product product;
  final List<LeftoverBatch> batches;

  Decimal get stock => dec(product.currentStock);
  Decimal get avgCost => dec(product.stockUnitCost);

  Decimal _qty(ShelfStatus status) => batches
      .where((b) => b.status == status)
      .fold(Decimal.zero, (sum, b) => sum + b.qty);

  Decimal get expiredQty => _qty(ShelfStatus.expired);
  Decimal get expiresTomorrowQty => _qty(ShelfStatus.expiresTomorrow);

  /// Kerugian jika [qty] dibuang = qty × HPP rata-rata stok (FR-4.7).
  int lossFor(Decimal qty) => toRupiah(qty * avgCost);
}

class DiscardInput {
  const DiscardInput({
    required this.productId,
    required this.qty,
    this.reason = WasteReason.expired,
    this.note,
  });

  final String productId;
  final Decimal qty;
  final WasteReason reason;
  final String? note;
}

/// Tutup hari: sisa menu ready stock disimpan atau dibuang (FR-4.6–4.8).
class DayCloseRepository {
  DayCloseRepository(this._db, this._products);

  final AppDatabase _db;
  final ProductRepository _products;

  /// Menu ready stock yang masih bersisa, dengan umur simpan tiap batch
  /// dihitung seolah produksi paling lama terjual lebih dulu.
  Future<List<Leftover>> leftovers(String businessId, DateTime today) async {
    final business = await (_db.select(
      _db.businesses,
    )..where((t) => t.id.equals(businessId))).getSingle();
    final products =
        await (_db.select(_db.products)
              ..where(
                (t) =>
                    t.businessId.equals(businessId) &
                    t.deletedAt.isNull() &
                    t.currentStock.isBiggerThanValue(0),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    final result = <Leftover>[];
    for (final p in products) {
      final mode = p.stockDeductMode ?? business.stockDeductMode;
      if (mode != StockDeductMode.onProduction) continue;
      final productions = await (_db.select(
        _db.productions,
      )..where((t) => t.productId.equals(p.id) & t.voidedAt.isNull())).get();
      final stock = dec(p.currentStock);
      final remaining = remainingBatches(
        productions: [
          for (final r in productions)
            ProductionBatch(
              producedOn: startOfDay(r.producedAt),
              qty: dec(r.outputQty),
            ),
        ],
        currentStock: stock,
      );
      final batches = [
        for (final b in remaining)
          LeftoverBatch(
            producedOn: b.producedOn,
            qty: b.qty,
            status: p.shelfLifeDays == null
                ? ShelfStatus.fresh
                : shelfStatus(
                    producedOn: b.producedOn,
                    shelfLifeDays: p.shelfLifeDays!,
                    today: startOfDay(today),
                  ),
          ),
      ];
      final covered = batches.fold(Decimal.zero, (s, b) => s + b.qty);
      if (stock > covered) {
        batches.add(
          LeftoverBatch(
            producedOn: null,
            qty: stock - covered,
            status: ShelfStatus.fresh,
          ),
        );
      }
      result.add(Leftover(product: p, batches: batches));
    }
    return result;
  }

  Future<bool> isClosed(String businessId, DateTime day) async {
    final business = await (_db.select(
      _db.businesses,
    )..where((t) => t.id.equals(businessId))).getSingle();
    final last = business.lastClosedOn;
    return last != null && dayKey(day).compareTo(last) <= 0;
  }

  /// Simpan keputusan Tutup hari untuk hari ini. Sisa yang tidak dibuang
  /// tetap jadi stok (bukan rugi); yang dibuang dicatat sebagai kerugian.
  Future<void> closeDay(
    String businessId,
    DateTime day,
    List<DiscardInput> discards,
  ) {
    final key = dayKey(day);
    final now = DateTime.now();
    final end = startOfDay(day).add(const Duration(hours: 23, minutes: 59));
    final at = now.isBefore(end) ? now : end;
    return _db.transaction(() async {
      for (final d in discards) {
        if (d.qty <= Decimal.zero) continue;
        await _products.issueProduct(
          d.productId,
          type: ProductMovementType.waste,
          qty: d.qty,
          at: at,
          reason: d.reason,
          refType: dayCloseRef,
          refId: key,
          note: d.note,
        );
      }
      final business = await (_db.select(
        _db.businesses,
      )..where((t) => t.id.equals(businessId))).getSingle();
      final last = business.lastClosedOn;
      if (last == null || key.compareTo(last) > 0) {
        await (_db.update(
          _db.businesses,
        )..where((t) => t.id.equals(businessId))).write(
          BusinessesCompanion(
            lastClosedOn: Value(key),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
    });
  }

  /// Membatalkan sisa yang dibuang pada Tutup hari tanggal [day] (FR-9.1);
  /// barangnya kembali ke stok menu jadi.
  Future<void> voidDayClose(DateTime day, {required String reason}) =>
      _db.transaction(
        () => _products.reverseProductByRef(dayCloseRef, dayKey(day), reason),
      );

  /// Sisa yang dibuang pada Tutup hari tanggal [day].
  Future<List<ProductStockMovement>> discardsOn(DateTime day) =>
      (_db.select(_db.productStockMovements)..where(
            (t) =>
                t.refType.equals(dayCloseRef) &
                t.refId.equals(dayKey(day)) &
                t.reversalOfId.isNull(),
          ))
          .get();
}
