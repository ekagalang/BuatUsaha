import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'product_repository.dart';

/// Harga khusus per menu per channel: productId → channelId → harga.
typedef ChannelPrices = Map<String, Map<String, int>>;

/// Harga [product] di [channelId]; tanpa harga khusus = harga utama.
int priceFor(Product product, String? channelId, ChannelPrices prices) =>
    channelId == null
    ? product.sellingPrice
    : prices[product.id]?[channelId] ?? product.sellingPrice;

/// Satu baris kartu Harga per channel (FR-14.1, FR-14.2).
class ChannelPriceRow {
  const ChannelPriceRow({
    required this.channel,
    required this.customPrice,
    required this.price,
    required this.feePerPcs,
    required this.profitPerPcs,
    required this.suggestion,
  });

  final SalesChannel channel;

  /// `null` = memakai harga utama.
  final int? customPrice;
  final int price;
  final Decimal feePerPcs;

  /// `null` selama HPP belum lengkap.
  final Decimal? profitPerPcs;
  final int? suggestion;
}

/// Satu menu yang terdampak simulasi harga bahan (FR-14.4).
class SimulationRow {
  const SimulationRow({
    required this.product,
    required this.oldHpp,
    required this.newHpp,
    required this.complete,
    required this.suggestedPrice,
  });

  final Product product;
  final Decimal oldHpp;
  final Decimal newHpp;

  /// HPP lengkap sebelum dan sesudah; laba dan saran hanya bila lengkap.
  final bool complete;
  final int? suggestedPrice;

  Decimal get delta => newHpp - oldHpp;
  Decimal get oldProfit => rupiah(product.sellingPrice) - oldHpp;
  Decimal get newProfit => rupiah(product.sellingPrice) - newHpp;
}

/// Harga per channel, riwayat HPP, dan simulasi kenaikan harga bahan (S4).
class PricingRepository {
  PricingRepository(this._db, this._products);

  final AppDatabase _db;
  final ProductRepository _products;

  Stream<ChannelPrices> watchChannelPrices(String businessId) {
    final query = _db.select(_db.productChannelPrices).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productChannelPrices.productId),
      ),
    ])..where(_db.products.businessId.equals(businessId));
    return query.watch().map((rows) {
      final prices = <String, Map<String, int>>{};
      for (final r in rows) {
        final p = r.readTable(_db.productChannelPrices);
        (prices[p.productId] ??= {})[p.channelId] = p.price;
      }
      return prices;
    });
  }

  /// [price] `null` = kembali memakai harga utama.
  Future<void> setChannelPrice(
    String productId,
    String channelId, {
    required int? price,
  }) async {
    if (price != null && price <= 0) {
      throw ArgumentError.value(price, 'price', 'harus > 0');
    }
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.productChannelPrices)..where(
                (t) =>
                    t.productId.equals(productId) &
                    t.channelId.equals(channelId),
              ))
              .getSingleOrNull();
      if (price == null) {
        if (existing != null) {
          await (_db.delete(
            _db.productChannelPrices,
          )..where((t) => t.id.equals(existing.id))).go();
        }
      } else if (existing == null) {
        await _db
            .into(_db.productChannelPrices)
            .insert(
              ProductChannelPricesCompanion.insert(
                productId: productId,
                channelId: channelId,
                price: price,
              ),
            );
      } else if (existing.price != price) {
        await (_db.update(
          _db.productChannelPrices,
        )..where((t) => t.id.equals(existing.id))).write(
          ProductChannelPricesCompanion(
            price: Value(price),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
    });
  }

  /// Rata-rata pcs per pesanan selesai lewat [channelId]; belum ada → semua
  /// pesanan selesai; belum ada juga → 1 (FR-14.2).
  Future<Decimal> averagePcsPerOrder(
    String businessId,
    String? channelId,
  ) async {
    Future<Decimal?> average({required bool byChannel}) async {
      final row = await _db
          .customSelect(
            'SELECT COUNT(DISTINCT o.id) AS n, COALESCE(SUM(i.qty), 0) AS pcs '
            'FROM orders o JOIN order_items i ON i.order_id = o.id '
            "WHERE o.business_id = ? AND o.status = 'COMPLETED' "
            'AND o.voided_at IS NULL'
            '${byChannel ? (channelId == null ? ' AND o.channel_id IS NULL' : ' AND o.channel_id = ?') : ''}',
            variables: [
              Variable.withString(businessId),
              if (byChannel && channelId != null)
                Variable.withString(channelId),
            ],
          )
          .getSingle();
      final n = row.read<int>('n');
      if (n == 0) return null;
      return divide(Decimal.fromInt(row.read<int>('pcs')), Decimal.fromInt(n));
    }

    return await average(byChannel: true) ??
        await average(byChannel: false) ??
        Decimal.one;
  }

  Stream<List<ChannelPriceRow>> watchChannelRows(String productId) async* {
    final product = await _products.watchProduct(productId).first;
    final businessId = product.product.businessId;
    await for (final _
        in _db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                _db.productChannelPrices,
                _db.salesChannels,
                _db.products,
                _db.businesses,
              ]),
            )
            .startWithNull()) {
      yield await channelRows(productId, businessId);
    }
  }

  Future<List<ChannelPriceRow>> channelRows(
    String productId,
    String businessId,
  ) async {
    final view = await _products.watchProduct(productId).first;
    final channels =
        await (_db.select(_db.salesChannels)..where(
              (t) => t.businessId.equals(businessId) & t.isActive.equals(true),
            ))
            .get();
    final prices = {
      for (final p in await (_db.select(
        _db.productChannelPrices,
      )..where((t) => t.productId.equals(productId))).get())
        p.channelId: p.price,
    };
    final rounding = view.business.priceRounding;
    final hasHpp = view.status != HppStatus.incomplete;
    return [
      for (final c in channels)
        await () async {
          final avg = await averagePcsPerOrder(businessId, c.id);
          final custom = prices[c.id];
          final price = custom ?? view.product.sellingPrice;
          final fee = channelFeePerPcs(
            price: price,
            commissionPct: dec(c.commissionPct),
            feePerOrder: c.feePerOrder,
            avgPcsPerOrder: avg,
          );
          return ChannelPriceRow(
            channel: c,
            customPrice: custom,
            price: price,
            feePerPcs: fee,
            profitPerPcs: hasHpp ? rupiah(price) - fee - view.hppPerPcs : null,
            suggestion: view.product.sellingPrice <= 0
                ? null
                : suggestChannelPrice(
                    directPrice: view.product.sellingPrice,
                    commissionPct: dec(c.commissionPct),
                    feePerOrder: c.feePerOrder,
                    avgPcsPerOrder: avg,
                    rounding: rounding,
                  ),
          );
        }(),
    ];
  }

  /// 30 perubahan terakhir, terbaru dulu (FR-14.3).
  Stream<List<ProductHppHistoryData>> watchHppHistory(String productId) =>
      (_db.select(_db.productHppHistory)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([(t) => OrderingTerm.desc(t.changedAt)])
            ..limit(30))
          .watch();

  /// HPP baru tiap menu bila harga bahan diganti [newUnitCost] (Rp per
  /// satuan dasar). Tidak menyimpan apa pun (FR-14.4).
  Future<List<SimulationRow>> simulate(
    String businessId,
    Map<String, Decimal> newUnitCost,
  ) async {
    if (newUnitCost.isEmpty) return const [];
    final views = await _products.watchProducts(businessId).first;
    final rows = <SimulationRow>[];
    for (final view in views) {
      final costing = view.costing;
      if (!costing.lines.any((l) => newUnitCost.containsKey(l.ingredient.id))) {
        continue;
      }
      final hpp = calculateHpp(
        lines: [
          for (final l in costing.lines)
            newUnitCost.containsKey(l.ingredient.id)
                ? RecipeLine(
                    ingredientId: l.ingredient.id,
                    qtyPerBatch: dec(l.item.qtyBase),
                    unitCost: newUnitCost[l.ingredient.id],
                  )
                : l.line,
        ],
        otherCosts: [
          for (final c in costing.costs)
            OtherCost(
              name: c.name,
              amount: costing.amountOf(c),
              basis: c.basis,
            ),
        ],
        yieldQty: view.product.yieldQty > 0
            ? dec(view.product.yieldQty)
            : Decimal.one,
      );
      final complete =
          view.status != HppStatus.incomplete &&
          hpp.status != HppStatus.incomplete;
      rows.add(
        SimulationRow(
          product: view.product,
          oldHpp: view.hppPerPcs,
          newHpp: hpp.hppPerPcs,
          complete: complete,
          suggestedPrice: complete ? _keepMargin(view, hpp.hppPerPcs) : null,
        ),
      );
    }
    rows.sort((a, b) => b.delta.compareTo(a.delta));
    return rows;
  }

  /// Saran harga supaya margin sama dengan sekarang; margin sekarang ≤ 0 →
  /// markup bawaan.
  int _keepMargin(ProductView view, Decimal newHpp) {
    final rounding = view.business.priceRounding;
    final margin = view.marginPct;
    if (margin == null || margin <= Decimal.zero) {
      return suggestPriceByMarkup(
        hppPerPcs: newHpp,
        markupPct: view.markupTarget,
        rounding: rounding,
      );
    }
    return suggestPriceByMargin(
      hppPerPcs: newHpp,
      marginPct: margin,
      rounding: rounding,
    );
  }
}

extension<T> on Stream<T> {
  Stream<T?> startWithNull() async* {
    yield null;
    yield* this;
  }
}
