import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'day_close_repository.dart';
import 'expense_repository.dart';

/// Angka satu menu untuk satu hari (FR-7.6).
class ProductDayReport {
  ProductDayReport({required this.product, required this.readyStock});

  final Product product;
  final bool readyStock;
  var made = Decimal.zero;
  var sold = 0;
  var kept = Decimal.zero;
  var discarded = Decimal.zero;
  var revenue = 0;
  var channelFee = 0;
  var cogs = Decimal.zero;
  var wasteLoss = Decimal.zero;
  var hasIncompleteHpp = false;

  Decimal get profit => rupiah(revenue) - rupiah(channelFee) - cogs - wasteLoss;

  bool get hasActivity =>
      made > Decimal.zero ||
      sold > 0 ||
      discarded > Decimal.zero ||
      kept > Decimal.zero;

  ProductDayLine get line => ProductDayLine(
    productId: product.id,
    revenue: revenue,
    cogs: cogs,
    channelFee: channelFee,
    wasteLoss: wasteLoss,
  );
}

class DayReport {
  const DayReport({
    required this.day,
    required this.products,
    required this.summary,
    required this.expenses,
    required this.closed,
  });

  final DateTime day;
  final List<ProductDayReport> products;
  final DaySummary summary;

  /// Pengeluaran bertanggal hari itu, tanpa pengeluaran bulanan (FR-7.7).
  final List<ExpenseView> expenses;
  final bool closed;

  ProductDayReport? get mostPressuring {
    final id = summary.mostPressuringProductId;
    if (id == null) return null;
    return products.where((p) => p.product.id == id).firstOrNull;
  }
}

class DayPoint {
  const DayPoint(this.day, this.revenue, this.profit);

  final DateTime day;
  final int revenue;

  /// Laba kotor setelah rugi produk dan bahan, sebelum pengeluaran.
  final int profit;
}

class ProductRank {
  ProductRank(this.product);

  final Product product;
  var qty = 0;
  var revenue = 0;
  var profit = Decimal.zero;
}

class ChannelRow {
  ChannelRow(this.name);

  final String name;
  var orders = 0;
  var revenue = 0;
  var fee = 0;
  var profit = Decimal.zero;
}

/// Laporan laba rugi periode (FR-7.5, FR-7.8).
class PeriodReport {
  const PeriodReport({
    required this.from,
    required this.to,
    required this.orders,
    required this.revenue,
    required this.channelFee,
    required this.cogs,
    required this.expenses,
    required this.productLoss,
    required this.materialLoss,
    required this.shipping,
    required this.trend,
    required this.products,
    required this.channels,
    required this.incompleteHppItems,
  });

  final DateTime from;
  final DateTime to;
  final int orders;
  final int revenue;
  final int channelFee;
  final int cogs;
  final int expenses;
  final int productLoss;
  final int materialLoss;

  /// Ongkir yang ditagih; dicatat terpisah dan bukan omzet (FR-7.4).
  final int shipping;
  final List<DayPoint> trend;
  final List<ProductRank> products;
  final List<ChannelRow> channels;

  /// Item terjual yang HPP-nya belum lengkap (FR-2.9).
  final int incompleteHppItems;

  int get grossProfit => revenue - channelFee - cogs;

  /// Margin laba kotor dalam persen; `null` jika belum ada omzet.
  Decimal? get marginPct => revenue <= 0
      ? null
      : divide(rupiah(grossProfit) * hundred, rupiah(revenue)).round(scale: 1);

  int get netProfit => grossProfit - productLoss - materialLoss - expenses;

  List<ProductRank> get bestSellers =>
      [...products]..sort((a, b) => b.qty.compareTo(a.qty));

  List<ProductRank> get mostProfitable =>
      [...products]..sort((a, b) => b.profit.compareTo(a.profit));
}

/// Ringkasan harian dan laporan periode dihitung dari transaksi
/// (bukan disimpan), jadi koreksi apa pun langsung tercermin.
class ReportRepository {
  ReportRepository(this._db);

  final AppDatabase _db;

  Stream<DayReport> watchDay(String businessId, DateTime day) =>
      _watch(() => dayReport(businessId, day));

  Stream<PeriodReport> watchPeriod(
    String businessId,
    DateTime from,
    DateTime to,
  ) => _watch(() => periodReport(businessId, from, to));

  Future<DayReport> dayReport(String businessId, DateTime day) async {
    final from = startOfDay(day);
    final to = from.add(const Duration(days: 1));
    final business = await _business(businessId);
    final products = await _products(businessId);
    final rows = {
      for (final p in products)
        p.id: ProductDayReport(
          product: p,
          readyStock:
              (p.stockDeductMode ?? business.stockDeductMode) ==
              StockDeductMode.onProduction,
        ),
    };

    for (final sale in await _sales(businessId, from, to)) {
      final r = rows[sale.productId];
      if (r == null) continue;
      r.sold += sale.qty;
      r.revenue += sale.revenue;
      r.channelFee += sale.fee;
      r.cogs += sale.cogs;
      r.hasIncompleteHpp |= sale.incomplete;
    }

    final productions =
        await (_db.select(_db.productions)..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.voidedAt.isNull() &
                  t.producedAt.isBiggerOrEqualValue(from.toUtc()) &
                  t.producedAt.isSmallerThanValue(to.toUtc()),
            ))
            .get();
    for (final p in productions) {
      final r = rows[p.productId];
      if (r != null && r.readyStock) r.made += dec(p.outputQty);
    }

    for (final m in await _productWaste(products, from, to)) {
      final r = rows[m.productId];
      if (r == null) continue;
      r.discarded -= dec(m.qty);
      r.wasteLoss -= rupiah(m.value);
    }

    for (final r in rows.values) {
      // Pre-order: jumlah dibuat = jumlah terjual.
      if (!r.readyStock) {
        r.made = Decimal.fromInt(r.sold);
        continue;
      }
      final last =
          await (_db.select(_db.productStockMovements)
                ..where(
                  (t) =>
                      t.productId.equals(r.product.id) &
                      t.occurredAt.isSmallerThanValue(to.toUtc()),
                )
                ..orderBy([
                  (t) => OrderingTerm.desc(t.occurredAt),
                  (t) => OrderingTerm.desc(t.createdAt),
                  (t) => OrderingTerm.desc(t.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      final balance = last == null ? Decimal.zero : dec(last.balanceAfter);
      r.kept = balance > Decimal.zero ? balance : Decimal.zero;
    }

    final expenses = (await _expenses(
      businessId,
      from,
      to,
    )).where((e) => !e.expense.isMonthly).toList();
    final active = rows.values.where((r) => r.hasActivity).toList()
      ..sort((a, b) => a.product.name.compareTo(b.product.name));
    final summary = summarizeDay(
      lines: [for (final r in active) r.line],
      expenses: expenses.fold(0, (s, e) => s + e.expense.amount),
      materialLoss: await _materialLoss(businessId, from, to),
    );
    final last = business.lastClosedOn;
    return DayReport(
      day: from,
      products: active,
      summary: summary,
      expenses: expenses,
      closed: last != null && dayKey(from).compareTo(last) <= 0,
    );
  }

  Future<PeriodReport> periodReport(
    String businessId,
    DateTime from,
    DateTime to,
  ) async {
    final start = startOfDay(from);
    final end = startOfDay(to);
    final products = await _products(businessId);
    final byId = {for (final p in products) p.id: p};
    final ranks = <String, ProductRank>{};
    final channels = <String, ChannelRow>{};
    final daily = <DateTime, (int, Decimal)>{};
    var revenue = 0, fee = 0, shipping = 0, orders = 0, incomplete = 0;
    var cogs = Decimal.zero;

    final sales = await _sales(businessId, start, end);
    final orderIds = <String>{};
    for (final s in sales) {
      revenue += s.revenue;
      fee += s.fee;
      cogs += s.cogs;
      if (s.incomplete) incomplete++;
      final product = byId[s.productId];
      if (product != null) {
        final r = ranks.putIfAbsent(s.productId, () => ProductRank(product));
        r.qty += s.qty;
        r.revenue += s.revenue;
        r.profit += s.profit;
      }
      final c = channels.putIfAbsent(s.channel, () => ChannelRow(s.channel));
      c.revenue += s.revenue;
      c.fee += s.fee;
      c.profit += s.profit;
      if (orderIds.add(s.orderId)) {
        c.orders++;
        orders++;
        shipping += s.shipping;
      }
      final day = startOfDay(s.completedAt);
      final (dr, dp) = daily[day] ?? (0, Decimal.zero);
      daily[day] = (dr + s.revenue, dp + s.profit);
    }

    var productLoss = Decimal.zero;
    for (final m in await _productWaste(products, start, end)) {
      productLoss -= rupiah(m.value);
      final day = startOfDay(m.occurredAt);
      final (dr, dp) = daily[day] ?? (0, Decimal.zero);
      daily[day] = (dr, dp + rupiah(m.value));
    }
    final materialLoss = await _materialLoss(businessId, start, end);
    final expenses = (await _expenses(
      businessId,
      start,
      end,
    )).fold(0, (s, e) => s + e.expense.amount);

    final trend = <DayPoint>[];
    for (
      var d = start;
      d.isBefore(end);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      final (r, p) = daily[d] ?? (0, Decimal.zero);
      trend.add(DayPoint(d, r, toRupiah(p)));
    }
    return PeriodReport(
      from: start,
      to: end,
      orders: orders,
      revenue: revenue,
      channelFee: fee,
      cogs: toRupiah(cogs),
      expenses: expenses,
      productLoss: toRupiah(productLoss),
      materialLoss: materialLoss,
      shipping: shipping,
      trend: trend,
      products: ranks.values.toList(),
      channels: channels.values.toList()
        ..sort((a, b) => b.revenue.compareTo(a.revenue)),
      incompleteHppItems: incomplete,
    );
  }

  // ---------------------------------------------------------- Internal

  /// Item pesanan yang selesai di `[from, to)` dan tidak dikoreksi; diskon dan
  /// potongan channel dibagi ke tiap item sesuai porsi nilainya.
  Future<List<_Sale>> _sales(
    String businessId,
    DateTime from,
    DateTime to,
  ) async {
    final orders =
        await (_db.select(_db.orders)..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.status.equalsValue(OrderStatus.completed) &
                  t.voidedAt.isNull() &
                  t.completedAt.isBiggerOrEqualValue(from.toUtc()) &
                  t.completedAt.isSmallerThanValue(to.toUtc()),
            ))
            .get();
    if (orders.isEmpty) return const [];
    final channels = {
      for (final c in await (_db.select(
        _db.salesChannels,
      )..where((t) => t.businessId.equals(businessId))).get())
        c.id: c.name,
    };
    final items = await (_db.select(
      _db.orderItems,
    )..where((t) => t.orderId.isIn([for (final o in orders) o.id]))).get();
    final byOrder = <String, List<OrderItem>>{};
    for (final i in items) {
      (byOrder[i.orderId] ??= []).add(i);
    }
    final sales = <_Sale>[];
    for (final o in orders) {
      final lines = byOrder[o.id] ?? const <OrderItem>[];
      final discounts = allocateProportionally(o.discount, [
        for (final l in lines) l.lineTotal,
      ]);
      final net = [
        for (final (i, l) in lines.indexed) l.lineTotal - discounts[i],
      ];
      final fees = allocateProportionally(o.channelFee, net);
      for (final (i, l) in lines.indexed) {
        sales.add(
          _Sale(
            orderId: o.id,
            productId: l.productId,
            channel: channels[o.channelId] ?? 'Langsung',
            completedAt: o.completedAt!,
            qty: l.qty,
            revenue: net[i],
            fee: fees[i],
            cogs: dec(l.hppPerPcsSnapshot ?? 0) * Decimal.fromInt(l.qty),
            incomplete: l.hppStatusSnapshot == HppStatus.incomplete,
            shipping: o.shippingFee,
          ),
        );
      }
    }
    return sales;
  }

  /// Mutasi WASTE produk jadi yang tidak dibatalkan; `value` negatif.
  Future<List<ProductStockMovement>> _productWaste(
    List<Product> products,
    DateTime from,
    DateTime to,
  ) async {
    if (products.isEmpty) return const [];
    final rows =
        await (_db.select(_db.productStockMovements)..where(
              (t) =>
                  t.productId.isIn([for (final p in products) p.id]) &
                  t.type.equalsValue(ProductMovementType.waste) &
                  t.occurredAt.isBiggerOrEqualValue(from.toUtc()) &
                  t.occurredAt.isSmallerThanValue(to.toUtc()),
            ))
            .get();
    final reversed = await _reversedIds(
      _db.productStockMovements,
      _db.productStockMovements.reversalOfId,
    );
    return [
      for (final r in rows)
        if (r.reversalOfId == null && !reversed.contains(r.id)) r,
    ];
  }

  /// Bahan rusak dan selisih opname (FR-7.5); selisih lebih mengurangi rugi.
  Future<int> _materialLoss(
    String businessId,
    DateTime from,
    DateTime to,
  ) async {
    final ingredientIds = [
      for (final i in await (_db.select(
        _db.ingredients,
      )..where((t) => t.businessId.equals(businessId))).get())
        i.id,
    ];
    if (ingredientIds.isEmpty) return 0;
    final rows =
        await (_db.select(_db.stockMovements)..where(
              (t) =>
                  t.ingredientId.isIn(ingredientIds) &
                  t.type.isInValues([MovementType.waste, MovementType.opname]) &
                  t.occurredAt.isBiggerOrEqualValue(from.toUtc()) &
                  t.occurredAt.isSmallerThanValue(to.toUtc()),
            ))
            .get();
    final reversed = await _reversedIds(
      _db.stockMovements,
      _db.stockMovements.reversalOfId,
    );
    return rows
        .where((r) => r.reversalOfId == null && !reversed.contains(r.id))
        .fold<int>(0, (sum, r) => sum - r.value);
  }

  Future<Set<String>> _reversedIds(
    TableInfo<Table, dynamic> table,
    GeneratedColumn<String> reversalOf,
  ) async {
    final query = _db.selectOnly(table)
      ..addColumns([reversalOf])
      ..where(reversalOf.isNotNull());
    return {for (final row in await query.get()) row.read(reversalOf)!};
  }

  Future<List<ExpenseView>> _expenses(
    String businessId,
    DateTime from,
    DateTime to,
  ) async {
    final all = await ExpenseRepository(_db)
        .watchExpenses(businessId, from: from, to: to)
        .first;
    return all.where((e) => e.expense.voidedAt == null).toList();
  }

  Future<List<Product>> _products(String businessId) => (_db.select(
    _db.products,
  )..where((t) => t.businessId.equals(businessId))).get();

  Future<Business> _business(String id) =>
      (_db.select(_db.businesses)..where((t) => t.id.equals(id))).getSingle();

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.orders,
        _db.orderItems,
        _db.productions,
        _db.productStockMovements,
        _db.stockMovements,
        _db.expenses,
        _db.businesses,
      ]),
    )) {
      yield await load();
    }
  }
}

class _Sale {
  const _Sale({
    required this.orderId,
    required this.productId,
    required this.channel,
    required this.completedAt,
    required this.qty,
    required this.revenue,
    required this.fee,
    required this.cogs,
    required this.incomplete,
    required this.shipping,
  });

  final String orderId;
  final String productId;
  final String channel;
  final DateTime completedAt;
  final int qty;
  final int revenue;
  final int fee;
  final Decimal cogs;
  final bool incomplete;
  final int shipping;

  Decimal get profit => rupiah(revenue) - rupiah(fee) - cogs;
}
