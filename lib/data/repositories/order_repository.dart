import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../domain/costing/costing.dart';
import '../../domain/orders/orders.dart';
import '../db/app_database.dart';
import '../db/decimal_convert.dart';
import 'cash_repository.dart';
import 'product_repository.dart';
import 'stock_repository.dart';

DateTime _now() => DateTime.now().toUtc();

const orderRef = 'order';
const orderVoidRef = 'order_void';

class OrderItemInput {
  const OrderItemInput({
    required this.productId,
    required this.qty,
    required this.unitPrice,
    this.note,
  });

  final String productId;
  final int qty;

  /// Bawaan = harga jual menu; boleh diubah per pesanan.
  final int unitPrice;
  final String? note;

  int get lineTotal => qty * unitPrice;
}

/// Pengingat pesanan (FR-6.1): H-1 jam [time], [minutes] sebelum jadwal, atau
/// waktu bebas [at].
class ReminderInput {
  const ReminderInput.dayBefore([this.time = '08:00'])
    : kind = ReminderKind.dayBefore,
      minutes = null,
      at = null;
  const ReminderInput.beforeDue([this.minutes = 120])
    : kind = ReminderKind.beforeDue,
      time = null,
      at = null;
  const ReminderInput.custom(DateTime this.at)
    : kind = ReminderKind.custom,
      time = null,
      minutes = null;

  final ReminderKind kind;
  final String? time;
  final int? minutes;
  final DateTime? at;

  DateTime remindAt(DateTime dueAt) =>
      reminderTime(kind, dueAt, time: time, minutes: minutes, at: at);
}

class OrderInput {
  const OrderInput({
    required this.dueAt,
    required this.items,
    this.type = OrderType.preOrder,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.channelId,
    this.fulfillment = Fulfillment.pickup,
    this.deliveryAddress,
    this.discount = 0,
    this.shippingFee = 0,
    this.channelFee,
    this.note,
    this.reminders,
  });

  final OrderType type;
  final DateTime dueAt;
  final List<OrderItemInput> items;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;

  /// `null` = Langsung.
  final String? channelId;
  final Fulfillment fulfillment;
  final String? deliveryAddress;
  final int discount;
  final int shippingFee;

  /// `null` = dihitung otomatis dari channel (FR-5.9).
  final int? channelFee;
  final String? note;

  /// `null` = pengingat bawaan dari pengaturan notifikasi.
  final List<ReminderInput>? reminders;

  int get subtotal => items.fold(0, (sum, i) => sum + i.lineTotal);

  /// Total item setelah diskon, tanpa ongkir: dasar omzet dan potongan
  /// channel.
  int get itemsRevenue => subtotal - discount;
  int get total => itemsRevenue + shippingFee;
}

class OrderLine {
  const OrderLine({required this.item, required this.product});

  final OrderItem item;
  final Product product;

  /// Snapshot HPP saat selesai (FR-7.2); sebelum selesai = perkiraan dari HPP
  /// menu terkini.
  Decimal get hppPerPcs {
    final snapshot = item.hppPerPcsSnapshot;
    if (snapshot != null) return dec(snapshot);
    return dec(product.hppPerPcs);
  }

  HppStatus get hppStatus => item.hppStatusSnapshot ?? product.hppStatus;
}

/// Pesanan beserta item, pelanggan, channel, pembayaran, dan labanya.
class OrderView {
  const OrderView({
    required this.order,
    required this.lines,
    this.customer,
    this.channel,
    this.payments = const [],
    this.reminders = const [],
    this.productions = const [],
  });

  final Order order;
  final List<OrderLine> lines;
  final Customer? customer;
  final SalesChannel? channel;
  final List<Payment> payments;
  final List<OrderReminder> reminders;
  final List<Production> productions;

  int get itemsRevenue => order.subtotal - order.discount;
  int get remaining => order.total - order.paidAmount;
  bool get isOpen =>
      order.status != OrderStatus.completed &&
      order.status != OrderStatus.cancelled;
  bool isLate(DateTime now) => isOrderLate(order.status, order.dueAt, now);

  int get cogs => toRupiah(
    lines.fold(
      Decimal.zero,
      (sum, l) => sum + l.hppPerPcs * Decimal.fromInt(l.item.qty),
    ),
  );

  /// Laba pesanan = omzet item − potongan channel − HPP (FR-5.6).
  int get profit => itemsRevenue - order.channelFee - cogs;

  /// Ada item yang HPP-nya belum lengkap (FR-2.9).
  bool get hasIncompleteHpp =>
      lines.any((l) => l.hppStatus == HppStatus.incomplete);

  int get pcs => lines.fold(0, (sum, l) => sum + l.item.qty);

  String get title =>
      customer?.name ??
      (order.type == OrderType.direct ? 'Penjualan langsung' : 'Tanpa nama');
}

class ProductNeed {
  const ProductNeed({
    required this.product,
    required this.orderedQty,
    required this.toMake,
  });

  final Product product;
  final int orderedQty;

  /// Ready stock: pesanan − stok menu jadi; pre-order: semua yang belum
  /// diproduksi.
  final Decimal toMake;
}

class IngredientNeed {
  const IngredientNeed({
    required this.ingredient,
    required this.requiredQty,
    required this.missingQty,
  });

  final Ingredient ingredient;
  final Decimal requiredQty;
  final Decimal missingQty;

  /// `null` jika bahan belum punya harga.
  Decimal? get estimatedCost => ingredient.avgUnitCost == null
      ? null
      : missingQty * dec(ingredient.avgUnitCost!);
}

/// Kebutuhan produksi untuk satu tanggal (FR-5.5) atau rentang tanggal
/// daftar belanja (FR-12.2).
class ProductionNeeds {
  const ProductionNeeds({
    required this.products,
    required this.ingredients,
    this.orderCount = 0,
  });

  final List<ProductNeed> products;
  final List<IngredientNeed> ingredients;

  /// Jumlah pesanan yang ikut dihitung.
  final int orderCount;

  List<IngredientNeed> get shortages =>
      ingredients.where((i) => i.missingQty > Decimal.zero).toList();
}

class ItemCorrection {
  const ItemCorrection({
    required this.line,
    required this.oldHpp,
    required this.newHpp,
  });

  final OrderLine line;
  final Decimal oldHpp;
  final Decimal newHpp;
}

/// Pesanan selesai yang snapshot HPP-nya berbeda dari hitungan ulang setelah
/// koreksi harga bahan (FR-9.5).
class OrderCorrection {
  const OrderCorrection({required this.view, required this.items});

  final OrderView view;
  final List<ItemCorrection> items;

  int get oldProfit => view.profit;

  int get newProfit {
    final changed = {for (final i in items) i.line.item.id: i.newHpp};
    final cogs = view.lines.fold(
      Decimal.zero,
      (sum, l) =>
          sum +
          (changed[l.item.id] ?? l.hppPerPcs) * Decimal.fromInt(l.item.qty),
    );
    return view.itemsRevenue - view.order.channelFee - toRupiah(cogs);
  }

  int get profitDelta => newProfit - oldProfit;
}

/// Stok produk jadi kurang untuk penjualan dan usaha tidak mengizinkan stok
/// minus (FR-4.9).
class InsufficientProductStockException implements Exception {
  const InsufficientProductStockException(this.shortages);

  /// Nama menu → jumlah yang kurang.
  final Map<String, Decimal> shortages;

  @override
  String toString() =>
      'Stok ${shortages.keys.join(', ')} tidak cukup. Catat produksi dulu.';
}

/// Pesanan, penjualan langsung, pembayaran, channel, dan pelanggan
/// (FR-5.x, FR-9.4).
class OrderRepository {
  OrderRepository(this._db, this._stock, this._products);

  final AppDatabase _db;
  final StockRepository _stock;
  final ProductRepository _products;

  // -------------------------------------------------------- Pesanan

  Future<String> createOrder(String businessId, OrderInput input) {
    _validate(input);
    return _db.transaction(() async {
      final customerId = await _customerFor(businessId, input);
      final count = await _countForDay(businessId, input.type, input.dueAt);
      final order = await _db
          .into(_db.orders)
          .insertReturning(
            OrdersCompanion.insert(
              businessId: businessId,
              orderNo: orderNumber(input.type, input.dueAt, count + 1),
              type: input.type,
              dueAt: input.dueAt.toUtc(),
              subtotal: input.subtotal,
              total: input.total,
              customerId: Value(customerId),
              channelId: Value(input.channelId),
              fulfillment: Value(input.fulfillment),
              deliveryAddress: Value(input.deliveryAddress),
              discount: Value(input.discount),
              shippingFee: Value(input.shippingFee),
              channelFee: Value(await _channelFeeFor(input)),
              note: Value(input.note),
            ),
          );
      await _writeItems(order.id, input.items);
      if (input.type == OrderType.preOrder) {
        await _writeReminders(
          order.id,
          input.dueAt,
          input.reminders ?? await defaultReminders(businessId),
        );
      }
      return order.id;
    });
  }

  /// Penjualan langsung (FR-5.7): langsung Selesai dan Lunas; stok menu
  /// ready stock langsung berkurang.
  Future<String> recordDirectSale(
    String businessId,
    OrderInput input, {
    PaymentMethod method = PaymentMethod.cash,
  }) {
    return _db.transaction(() async {
      final at = input.dueAt;
      final id = await createOrder(
        businessId,
        OrderInput(
          type: OrderType.direct,
          dueAt: at,
          items: input.items,
          customerName: input.customerName,
          customerPhone: input.customerPhone,
          channelId: input.channelId,
          discount: input.discount,
          shippingFee: input.shippingFee,
          channelFee: input.channelFee,
          note: input.note,
          reminders: const [],
        ),
      );
      await completeOrder(id, at: at);
      await addPayment(
        id,
        amount: input.total,
        method: method,
        kind: PaymentKind.settlement,
        paidAt: at,
      );
      return id;
    });
  }

  /// Ubah pesanan yang belum selesai; pengingat dihitung ulang dari jadwal
  /// baru (FR-6.6).
  Future<void> updateOrder(String orderId, OrderInput input) {
    _validate(input);
    return _db.transaction(() async {
      final order = await _order(orderId);
      if (order.status == OrderStatus.completed ||
          order.status == OrderStatus.cancelled) {
        throw StateError('Pesanan yang sudah selesai atau batal tidak diubah.');
      }
      final customerId = await _customerFor(order.businessId, input);
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          dueAt: Value(input.dueAt.toUtc()),
          subtotal: Value(input.subtotal),
          total: Value(input.total),
          customerId: Value(customerId),
          channelId: Value(input.channelId),
          fulfillment: Value(input.fulfillment),
          deliveryAddress: Value(input.deliveryAddress),
          discount: Value(input.discount),
          shippingFee: Value(input.shippingFee),
          channelFee: Value(await _channelFeeFor(input)),
          note: Value(input.note),
          updatedAt: Value(_now()),
        ),
      );
      await _replaceItems(orderId, input.items);
      await _replaceReminders(
        orderId,
        input.dueAt,
        input.reminders ?? await defaultReminders(order.businessId),
      );
      await _refreshPayment(orderId);
    });
  }

  /// Baru → Diproses → Siap. Selesai lewat [completeOrder], Batal lewat
  /// [cancelOrder].
  Future<void> setStatus(String orderId, OrderStatus status) async {
    if (status == OrderStatus.completed) return completeOrder(orderId);
    if (status == OrderStatus.cancelled) {
      throw ArgumentError('Pakai cancelOrder untuk membatalkan.');
    }
    final order = await _order(orderId);
    if (order.status == OrderStatus.completed ||
        order.status == OrderStatus.cancelled) {
      throw StateError('Pesanan ini sudah selesai atau batal.');
    }
    await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
      OrdersCompanion(status: Value(status), updatedAt: Value(_now())),
    );
  }

  /// Selesaikan pesanan (FR-7.1, FR-7.2): omzet diakui hari ini, snapshot
  /// HPP disimpan, stok menu ready stock dikurangi, bahan menu pre-order
  /// dipotong (kecuali sudah lewat produksi yang ditautkan ke pesanan ini).
  Future<void> completeOrder(String orderId, {DateTime? at}) {
    final when = (at ?? _now()).toUtc();
    return _db.transaction(() async {
      final view = await loadOrder(orderId);
      final order = view.order;
      if (order.status == OrderStatus.completed ||
          order.status == OrderStatus.cancelled) {
        throw StateError('Pesanan ini sudah selesai atau batal.');
      }
      final business = await _business(order.businessId);
      final linked = view.productions.where((p) => p.voidedAt == null);

      // Cek stok produk jadi lebih dulu (FR-4.9).
      final needByProduct = <String, Decimal>{};
      for (final l in view.lines) {
        if (_isReadyStock(l.product, business)) {
          needByProduct.update(
            l.product.id,
            (q) => q + Decimal.fromInt(l.item.qty),
            ifAbsent: () => Decimal.fromInt(l.item.qty),
          );
        }
      }
      if (!business.allowNegativeStock) {
        final short = <String, Decimal>{};
        for (final l in view.lines) {
          final need = needByProduct[l.product.id];
          if (need == null || short.containsKey(l.product.name)) continue;
          final stock = dec(l.product.currentStock);
          if (need > stock) short[l.product.name] = need - stock;
        }
        if (short.isNotEmpty) throw InsufficientProductStockException(short);
      }

      final usage = <String, Decimal>{};
      for (final l in view.lines) {
        final qty = Decimal.fromInt(l.item.qty);
        Decimal hpp;
        if (_isReadyStock(l.product, business)) {
          final unit = await _products.issueProduct(
            l.product.id,
            type: ProductMovementType.sale,
            qty: qty,
            at: when,
            refType: orderRef,
            refId: orderId,
          );
          hpp = unit > Decimal.zero ? unit : dec(l.product.hppPerPcs);
        } else {
          final made = linked.where((p) => p.productId == l.product.id);
          final output = made.fold(
            Decimal.zero,
            (s, p) => s + dec(p.outputQty),
          );
          if (output > Decimal.zero) {
            final cost = made.fold(
              0,
              (s, p) => s + p.materialCost + p.otherCost,
            );
            hpp = divide(rupiah(cost), output);
          } else {
            hpp = dec(l.product.hppPerPcs);
            final costing = await _products.costingOf(l.product.id);
            final batches = divide(qty, dec(l.product.yieldQty));
            for (final r in costing.lines) {
              usage.update(
                r.ingredient.id,
                (q) => q + dec(r.item.qtyBase) * batches,
                ifAbsent: () => dec(r.item.qtyBase) * batches,
              );
            }
          }
        }
        await (_db.update(
          _db.orderItems,
        )..where((t) => t.id.equals(l.item.id))).write(
          OrderItemsCompanion(
            hppPerPcsSnapshot: Value(dbl(hpp)),
            hppStatusSnapshot: Value(l.product.hppStatus),
            updatedAt: Value(_now()),
          ),
        );
      }
      if (usage.isNotEmpty) {
        await _stock.recordUsage(
          type: MovementType.orderUsage,
          refType: orderRef,
          refId: orderId,
          usage: usage,
          at: when,
        );
      }
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value(OrderStatus.completed),
          completedAt: Value(when),
          updatedAt: Value(_now()),
        ),
      );
      await _cancelReminders(orderId, keepPayment: true);
    });
  }

  /// Batal sebelum Selesai (FR-5.3). Uang yang sudah masuk dikembalikan
  /// lewat [refund] jika diisi.
  Future<void> cancelOrder(
    String orderId, {
    required String reason,
    int refund = 0,
    PaymentMethod refundMethod = PaymentMethod.cash,
  }) {
    return _db.transaction(() async {
      final order = await _order(orderId);
      if (order.status == OrderStatus.completed) {
        throw StateError(
          'Pesanan selesai dibatalkan lewat koreksi (voidCompletedOrder).',
        );
      }
      if (order.status == OrderStatus.cancelled) {
        throw StateError('Pesanan ini sudah batal.');
      }
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value(OrderStatus.cancelled),
          cancelledAt: Value(_now()),
          voidReason: Value(reason),
          updatedAt: Value(_now()),
        ),
      );
      if (refund > 0) await _insertRefund(orderId, refund, refundMethod);
      await _cancelReminders(orderId);
      await _refreshPayment(orderId);
    });
  }

  /// Koreksi pesanan yang sudah Selesai (FR-9.4): omzetnya dibalik (tidak
  /// lagi dihitung di tanggal selesainya), uang kembali dicatat sebagai
  /// REFUND, dan barangnya kembali ke stok menu jadi atau dicatat dibuang.
  /// Barang menu pre-order tidak bisa kembali ke stok, jadi selalu jadi rugi.
  Future<void> voidCompletedOrder(
    String orderId, {
    required String reason,
    int refund = 0,
    PaymentMethod refundMethod = PaymentMethod.cash,
    bool returnToStock = true,
  }) {
    return _db.transaction(() async {
      final view = await loadOrder(orderId);
      final order = view.order;
      if (order.status != OrderStatus.completed || order.voidedAt != null) {
        throw StateError('Hanya pesanan selesai yang dikoreksi di sini.');
      }
      final at = order.completedAt!;
      // Menu yang terjual dari stok menu jadi saat pesanan ini selesai.
      final fromStock = {
        for (final m
            in await (_db.select(_db.productStockMovements)..where(
                  (t) =>
                      t.refType.equals(orderRef) &
                      t.refId.equals(orderId) &
                      t.reversalOfId.isNull(),
                ))
                .get())
          m.productId,
      };
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value(OrderStatus.cancelled),
          voidedAt: Value(_now()),
          voidReason: Value(reason),
          cancelledAt: Value(_now()),
          updatedAt: Value(_now()),
        ),
      );
      await _products.reverseProductByRef(orderRef, orderId, reason);
      for (final l in view.lines) {
        final qty = Decimal.fromInt(l.item.qty);
        final readyStock = fromStock.contains(l.product.id);
        if (readyStock && returnToStock) continue;
        if (!readyStock) {
          // Barang pre-order tidak pernah masuk stok: catat masuk dengan
          // HPP snapshot-nya lalu dibuang, supaya kerugiannya tercatat.
          await _products.receiveProduct(
            l.product.id,
            qty: qty,
            unitCost: l.hppPerPcs,
            at: at,
            refType: orderVoidRef,
            refId: orderId,
            note: reason,
          );
        }
        await _products.issueProduct(
          l.product.id,
          type: ProductMovementType.waste,
          qty: qty,
          at: at,
          reason: WasteReason.other,
          refType: orderVoidRef,
          refId: orderId,
          note: reason,
        );
      }
      if (refund > 0) await _insertRefund(orderId, refund, refundMethod);
      await _cancelReminders(orderId);
      await _refreshPayment(orderId);
    });
  }

  // ------------------------------------------------------ Pembayaran

  Future<String> addPayment(
    String orderId, {
    required int amount,
    required PaymentMethod method,
    PaymentKind kind = PaymentKind.dp,
    DateTime? paidAt,
    String? note,
  }) {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'harus > 0');
    return _db.transaction(() async {
      final payment = await _db
          .into(_db.payments)
          .insertReturning(
            PaymentsCompanion.insert(
              orderId: orderId,
              amount: amount,
              method: method,
              kind: kind,
              paidAt: (paidAt ?? _now()).toUtc(),
              note: Value(note),
              cashAccountId: Value(await _cashAccountFor(orderId, method)),
            ),
          );
      await _refreshPayment(orderId);
      return payment.id;
    });
  }

  Future<void> voidPayment(String paymentId, {required String reason}) {
    return _db.transaction(() async {
      final payment = await (_db.select(
        _db.payments,
      )..where((t) => t.id.equals(paymentId))).getSingle();
      if (payment.voidedAt != null) {
        throw StateError('Pembayaran ini sudah dibatalkan.');
      }
      await (_db.update(
        _db.payments,
      )..where((t) => t.id.equals(paymentId))).write(
        PaymentsCompanion(
          voidedAt: Value(_now()),
          voidReason: Value(reason),
          updatedAt: Value(_now()),
        ),
      );
      await _refreshPayment(payment.orderId);
    });
  }

  // ---------------------------------------------------------- Baca

  Future<OrderView> loadOrder(String orderId) async {
    final order = await _order(orderId);
    return (await _views([order], detail: true)).single;
  }

  Stream<OrderView> watchOrder(String orderId) =>
      _watch(() => loadOrder(orderId));

  Stream<List<OrderView>> watchOrders(
    String businessId, {
    DateTime? from,
    DateTime? to,
  }) => _watch(() => listOrders(businessId, from: from, to: to));

  /// Pesanan dengan jadwal di antara [from] (inklusif) dan [to] (eksklusif),
  /// urut jadwal; [completedFrom]/[completedTo] menyaring tanggal selesai.
  Future<List<OrderView>> listOrders(
    String businessId, {
    DateTime? from,
    DateTime? to,
    DateTime? completedFrom,
    DateTime? completedTo,
    List<OrderStatus>? statuses,
    bool detail = false,
  }) async {
    final query = _db.select(_db.orders)
      ..where((t) {
        var cond = t.businessId.equals(businessId) & t.deletedAt.isNull();
        if (from != null) {
          cond = cond & t.dueAt.isBiggerOrEqualValue(from.toUtc());
        }
        if (to != null) cond = cond & t.dueAt.isSmallerThanValue(to.toUtc());
        if (completedFrom != null) {
          cond =
              cond & t.completedAt.isBiggerOrEqualValue(completedFrom.toUtc());
        }
        if (completedTo != null) {
          cond = cond & t.completedAt.isSmallerThanValue(completedTo.toUtc());
        }
        if (statuses != null) cond = cond & t.status.isInValues(statuses);
        return cond;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]);
    return _views(await query.get(), detail: detail);
  }

  /// Pesanan yang belum selesai dan sudah lewat jadwal, untuk Beranda.
  Future<List<OrderView>> openOrdersDueBefore(
    String businessId,
    DateTime to,
  ) async {
    final rows =
        await (_db.select(_db.orders)
              ..where(
                (t) =>
                    t.businessId.equals(businessId) &
                    t.dueAt.isSmallerThanValue(to.toUtc()) &
                    t.status.isNotInValues([
                      OrderStatus.completed,
                      OrderStatus.cancelled,
                    ]),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
            .get();
    return _views(rows);
  }

  Stream<ProductionNeeds> watchProductionNeeds(
    String businessId,
    DateTime day,
  ) => _watch(() => productionNeeds(businessId, day));

  /// Total pcs per menu untuk pesanan tanggal [day] (lokal) dan cukup
  /// tidaknya stok bahan (FR-5.5).
  Future<ProductionNeeds> productionNeeds(String businessId, DateTime day) {
    final local = day.toLocal();
    final from = DateTime(local.year, local.month, local.day);
    return productionNeedsBetween(
      businessId,
      from,
      from.add(const Duration(days: 1)),
    );
  }

  /// Kebutuhan untuk pesanan berjadwal di `[from, to)`. Dengan [safetyStock],
  /// stok jaga menu ready stock ikut dihitung, termasuk menu yang tidak
  /// dipesan (FR-12.2).
  Future<ProductionNeeds> productionNeedsBetween(
    String businessId,
    DateTime from,
    DateTime to, {
    bool safetyStock = false,
  }) async {
    final business = await _business(businessId);
    final rows =
        await (_db.select(_db.orders)..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.dueAt.isBiggerOrEqualValue(from.toUtc()) &
                  t.dueAt.isSmallerThanValue(to.toUtc()) &
                  t.status.isNotInValues([
                    OrderStatus.completed,
                    OrderStatus.cancelled,
                  ]),
            ))
            .get();
    final views = await _views(rows, detail: true);
    final ordered = <String, int>{};
    final made = <String, Decimal>{};
    final products = <String, Product>{};
    for (final v in views) {
      for (final l in v.lines) {
        ordered.update(
          l.product.id,
          (q) => q + l.item.qty,
          ifAbsent: () => l.item.qty,
        );
        products[l.product.id] = l.product;
      }
      for (final p in v.productions.where((p) => p.voidedAt == null)) {
        made.update(
          p.productId,
          (q) => q + dec(p.outputQty),
          ifAbsent: () => dec(p.outputQty),
        );
      }
    }
    if (safetyStock) {
      final guarded =
          await (_db.select(_db.products)..where(
                (t) =>
                    t.businessId.equals(businessId) &
                    t.isActive.equals(true) &
                    t.archivedAt.isNull() &
                    t.deletedAt.isNull() &
                    t.safetyStock.isBiggerThanValue(0),
              ))
              .get();
      for (final p in guarded) {
        if (!_isReadyStock(p, business)) continue;
        products.putIfAbsent(p.id, () => p);
        ordered.putIfAbsent(p.id, () => 0);
      }
    }
    final needs = <ProductNeed>[];
    final required = <String, Decimal>{};
    final ingredients = <String, Ingredient>{};
    for (final MapEntry(key: id, value: qty) in ordered.entries) {
      final product = products[id]!;
      final ready = _isReadyStock(product, business);
      final have = ready
          ? dec(product.currentStock)
          : (made[id] ?? Decimal.zero);
      final guard = safetyStock && ready
          ? dec(product.safetyStock)
          : Decimal.zero;
      final diff =
          Decimal.fromInt(qty) +
          guard -
          (have < Decimal.zero ? Decimal.zero : have);
      final toMake = diff > Decimal.zero ? diff : Decimal.zero;
      needs.add(ProductNeed(product: product, orderedQty: qty, toMake: toMake));
      if (toMake == Decimal.zero) continue;
      final costing = await _products.costingOf(id);
      final batches = divide(toMake, dec(product.yieldQty));
      for (final r in costing.lines) {
        ingredients[r.ingredient.id] = r.ingredient;
        required.update(
          r.ingredient.id,
          (q) => q + dec(r.item.qtyBase) * batches,
          ifAbsent: () => dec(r.item.qtyBase) * batches,
        );
      }
    }
    needs.sort((a, b) => a.product.name.compareTo(b.product.name));
    return ProductionNeeds(
      orderCount: rows.length,
      products: needs,
      ingredients: [
        for (final MapEntry(key: id, value: qty) in required.entries)
          () {
            final ingredient = ingredients[id]!;
            final stock = dec(ingredient.currentStock);
            final available = stock < Decimal.zero ? Decimal.zero : stock;
            final missing = qty - available;
            return IngredientNeed(
              ingredient: ingredient,
              requiredQty: qty,
              missingQty: missing > Decimal.zero ? missing : Decimal.zero,
            );
          }(),
      ]..sort((a, b) => a.ingredient.name.compareTo(b.ingredient.name)),
    );
  }

  // ------------------------------------------------ Channel & pelanggan

  Stream<List<SalesChannel>> watchChannels(
    String businessId, {
    bool activeOnly = false,
  }) =>
      (_db.select(_db.salesChannels)
            ..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.deletedAt.isNull() &
                  (activeOnly ? t.isActive.equals(true) : const Constant(true)),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  Future<void> saveChannel(
    String businessId, {
    String? id,
    required String name,
    required Decimal commissionPct,
    int feePerOrder = 0,
    int feePerPcs = 0,
    bool isActive = true,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Nama channel belum diisi.');
    final companion = SalesChannelsCompanion(
      name: Value(name.trim()),
      commissionPct: Value(dbl(commissionPct)),
      feePerOrder: Value(feePerOrder),
      feePerPcs: Value(feePerPcs),
      isActive: Value(isActive),
      updatedAt: Value(_now()),
    );
    if (id == null) {
      await _db
          .into(_db.salesChannels)
          .insert(companion.copyWith(businessId: Value(businessId)));
    } else {
      await (_db.update(
        _db.salesChannels,
      )..where((t) => t.id.equals(id))).write(companion);
    }
  }

  /// Potongan bawaan channel untuk total item tertentu (FR-5.9).
  Future<int> suggestedChannelFee(
    String? channelId,
    int itemsRevenue, {
    int pcs = 0,
  }) async {
    if (channelId == null || itemsRevenue <= 0) return 0;
    final channel = await (_db.select(
      _db.salesChannels,
    )..where((t) => t.id.equals(channelId))).getSingle();
    return channelFee(
      itemsTotal: itemsRevenue,
      commissionPct: dec(channel.commissionPct),
      feePerOrder: channel.feePerOrder,
      feePerPcs: channel.feePerPcs,
      pcs: pcs,
    );
  }

  Future<List<Customer>> searchCustomers(String businessId, String query) {
    final q = query.trim().toLowerCase();
    return (_db.select(_db.customers)
          ..where(
            (t) =>
                t.businessId.equals(businessId) &
                (t.name.lower().like('%$q%') | t.phoneWa.like('%$q%')),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(8))
        .get();
  }

  /// Pengingat bawaan dari pengaturan notifikasi (FR-6.1).
  Future<List<ReminderInput>> defaultReminders(String businessId) async {
    final settings = await (_db.select(
      _db.notificationSettings,
    )..where((t) => t.businessId.equals(businessId))).getSingleOrNull();
    if (settings == null) {
      return const [ReminderInput.dayBefore(), ReminderInput.beforeDue()];
    }
    final list = jsonDecode(settings.defaultOffsets) as List<dynamic>;
    return [
      for (final raw in list.cast<Map<String, dynamic>>())
        switch (raw['type']) {
          'DAY_BEFORE' => ReminderInput.dayBefore(
            raw['time'] as String? ?? '08:00',
          ),
          _ => ReminderInput.beforeDue(raw['minutes'] as int? ?? 120),
        },
    ];
  }

  /// Bentuk ulang pengingat tersimpan menjadi isian form.
  static List<ReminderInput> remindersOf(OrderView view) => [
    for (final r in view.reminders)
      switch (r.kind) {
        ReminderKind.dayBefore => ReminderInput.dayBefore(
          '${r.remindAt.toLocal().hour.toString().padLeft(2, '0')}:'
          '${r.remindAt.toLocal().minute.toString().padLeft(2, '0')}',
        ),
        ReminderKind.beforeDue => ReminderInput.beforeDue(
          view.order.dueAt.difference(r.remindAt).inMinutes,
        ),
        _ => ReminderInput.custom(r.remindAt),
      },
  ];

  // ------------------------------------------- Koreksi HPP (FR-9.5)

  Stream<List<OrderCorrection>> watchCostCorrections(String businessId) =>
      _watch(() => costCorrections(businessId), extra: [_db.stockMovements]);

  /// Pesanan selesai yang HPP-nya berubah setelah koreksi harga bahan.
  /// Snapshot tidak diubah otomatis; pengguna memilih lewat [applyCostCorrection].
  Future<List<OrderCorrection>> costCorrections(String businessId) async {
    final orders = await listOrders(
      businessId,
      statuses: const [OrderStatus.completed],
      detail: true,
    );
    final result = <OrderCorrection>[];
    for (final view in orders) {
      if (view.order.voidedAt != null) continue;
      final items = await _corrections(view);
      if (items.isNotEmpty) {
        result.add(OrderCorrection(view: view, items: items));
      }
    }
    result.sort(
      (a, b) => b.view.order.completedAt!.compareTo(a.view.order.completedAt!),
    );
    return result;
  }

  /// Simpan HPP hasil hitung ulang ke snapshot item pesanan ini.
  Future<void> applyCostCorrection(String orderId) {
    return _db.transaction(() async {
      final view = await loadOrder(orderId);
      for (final c in await _corrections(view)) {
        await (_db.update(
          _db.orderItems,
        )..where((t) => t.id.equals(c.line.item.id))).write(
          OrderItemsCompanion(
            hppPerPcsSnapshot: Value(dbl(c.newHpp)),
            updatedAt: Value(_now()),
          ),
        );
      }
    });
  }

  Future<List<ItemCorrection>> _corrections(OrderView view) async {
    final orderId = view.order.id;
    final sales =
        await (_db.select(_db.productStockMovements)..where(
              (t) =>
                  t.refType.equals(orderRef) &
                  t.refId.equals(orderId) &
                  t.type.equalsValue(ProductMovementType.sale) &
                  t.reversalOfId.isNull(),
            ))
            .get();
    final linked = view.productions.where((p) => p.voidedAt == null);
    final usage =
        await (_db.select(_db.stockMovements)..where(
              (t) =>
                  t.refType.equals(orderRef) &
                  t.refId.equals(orderId) &
                  t.reversalOfId.isNull(),
            ))
            .get();

    // Pre-order tanpa produksi: selisih harga bahan saat dicatat vs sekarang,
    // dibagi ke item sesuai takaran resepnya.
    final usageLines = <OrderLine>[];
    final recipeUse = <String, Map<String, Decimal>>{};
    for (final l in view.lines) {
      final fromStock = sales.any((m) => m.productId == l.product.id);
      final made = linked.any((p) => p.productId == l.product.id);
      if (fromStock || made) continue;
      usageLines.add(l);
      final costing = await _products.costingOf(l.product.id);
      final batches = divide(
        Decimal.fromInt(l.item.qty),
        dec(l.product.yieldQty),
      );
      recipeUse[l.item.id] = {
        for (final r in costing.lines)
          r.ingredient.id: dec(r.item.qtyBase) * batches,
      };
    }
    final usageDelta = <String, Decimal>{};
    for (final m in usage) {
      final then = await _stock.unitCostAsRecorded(m);
      final delta = -dec(m.qtyBase) * (dec(m.unitCost) - then);
      if (delta == Decimal.zero) continue;
      usageDelta.update(
        m.ingredientId,
        (d) => d + delta,
        ifAbsent: () => delta,
      );
    }

    final corrections = <ItemCorrection>[];
    for (final l in view.lines) {
      final snapshot = l.item.hppPerPcsSnapshot;
      if (snapshot == null) continue;
      final qty = Decimal.fromInt(l.item.qty);
      Decimal? recalculated;
      final mine = sales.where((m) => m.productId == l.product.id).toList();
      final made = linked.where((p) => p.productId == l.product.id).toList();
      if (mine.isNotEmpty) {
        var units = Decimal.zero;
        var cost = Decimal.zero;
        for (final m in mine) {
          units += -dec(m.qty);
          cost += -dec(m.qty) * dec(m.unitCost);
        }
        if (units > Decimal.zero && cost > Decimal.zero) {
          recalculated = divide(cost, units);
        }
      } else if (made.isNotEmpty) {
        final output = made.fold(Decimal.zero, (s, p) => s + dec(p.outputQty));
        final cost = made.fold(0, (s, p) => s + p.materialCost + p.otherCost);
        if (output > Decimal.zero) recalculated = divide(rupiah(cost), output);
      } else if (usageDelta.isNotEmpty) {
        var delta = Decimal.zero;
        final use = recipeUse[l.item.id] ?? const <String, Decimal>{};
        for (final MapEntry(key: ingredientId, value: d)
            in usageDelta.entries) {
          final mineUse = use[ingredientId] ?? Decimal.zero;
          if (mineUse == Decimal.zero) continue;
          final total = usageLines.fold(
            Decimal.zero,
            (s, o) => s + (recipeUse[o.item.id]?[ingredientId] ?? Decimal.zero),
          );
          delta += d * divide(mineUse, total);
        }
        recalculated = dec(snapshot) + divide(delta, qty);
      }
      if (recalculated == null) continue;
      final change = toRupiah((recalculated - dec(snapshot)) * qty);
      if (change == 0) continue;
      corrections.add(
        ItemCorrection(line: l, oldHpp: dec(snapshot), newHpp: recalculated),
      );
    }
    return corrections;
  }

  // ---------------------------------------------------------- Internal

  void _validate(OrderInput input) {
    if (input.items.isEmpty) throw ArgumentError('Pesanan belum punya item.');
    for (final i in input.items) {
      if (i.qty <= 0) throw ArgumentError.value(i.qty, 'qty', 'harus > 0');
      if (i.unitPrice < 0) {
        throw ArgumentError.value(i.unitPrice, 'unitPrice', 'harus ≥ 0');
      }
    }
    if (input.discount < 0 || input.discount > input.subtotal) {
      throw ArgumentError.value(input.discount, 'discount', 'tidak valid');
    }
    if (input.shippingFee < 0) {
      throw ArgumentError.value(input.shippingFee, 'shippingFee', 'harus ≥ 0');
    }
  }

  bool _isReadyStock(Product product, Business business) =>
      (product.stockDeductMode ?? business.stockDeductMode) ==
      StockDeductMode.onProduction;

  Future<int> _channelFeeFor(OrderInput input) async =>
      input.channelFee ??
      await suggestedChannelFee(
        input.channelId,
        input.itemsRevenue,
        pcs: input.items.fold(0, (sum, i) => sum + i.qty),
      );

  Future<String?> _customerFor(String businessId, OrderInput input) async {
    final name = input.customerName?.trim() ?? '';
    final phone = input.customerPhone?.trim() ?? '';
    if (name.isEmpty && phone.isEmpty) return null;
    Customer? existing;
    if (phone.isNotEmpty) {
      existing =
          await (_db.select(_db.customers)
                ..where(
                  (t) =>
                      t.businessId.equals(businessId) & t.phoneWa.equals(phone),
                )
                ..limit(1))
              .getSingleOrNull();
    }
    existing ??= name.isEmpty
        ? null
        : await (_db.select(_db.customers)
                ..where(
                  (t) =>
                      t.businessId.equals(businessId) &
                      t.name.lower().equals(name.toLowerCase()),
                )
                ..limit(1))
              .getSingleOrNull();
    final address = input.customerAddress?.trim();
    if (existing != null) {
      await (_db.update(
        _db.customers,
      )..where((t) => t.id.equals(existing!.id))).write(
        CustomersCompanion(
          name: name.isEmpty ? const Value.absent() : Value(name),
          phoneWa: phone.isEmpty ? const Value.absent() : Value(phone),
          address: address == null || address.isEmpty
              ? const Value.absent()
              : Value(address),
          updatedAt: Value(_now()),
        ),
      );
      return existing.id;
    }
    final created = await _db
        .into(_db.customers)
        .insertReturning(
          CustomersCompanion.insert(
            businessId: businessId,
            name: name.isEmpty ? phone : name,
            phoneWa: Value(phone.isEmpty ? null : phone),
            address: Value(address == null || address.isEmpty ? null : address),
          ),
        );
    return created.id;
  }

  Future<int> _countForDay(
    String businessId,
    OrderType type,
    DateTime dueAt,
  ) async {
    final prefix = orderNumber(
      type,
      dueAt,
      0,
    ).replaceFirst(RegExp(r'000$'), '');
    final rows =
        await (_db.select(_db.orders)..where(
              (t) =>
                  t.businessId.equals(businessId) & t.orderNo.like('$prefix%'),
            ))
            .get();
    // Nomor terbesar, bukan jumlah: setelah sinkron dua HP nomor bisa
    // bolong (FR-10.4).
    var max = 0;
    for (final row in rows) {
      final n = int.tryParse(row.orderNo.substring(prefix.length)) ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  Future<void> _writeItems(String orderId, List<OrderItemInput> items) async {
    for (final i in items) {
      await _db
          .into(_db.orderItems)
          .insert(
            OrderItemsCompanion.insert(
              orderId: orderId,
              productId: i.productId,
              qty: i.qty,
              unitPrice: i.unitPrice,
              lineTotal: i.lineTotal,
              note: Value(i.note),
            ),
          );
    }
  }

  /// Item dan pengingat pesanan yang diubah diperbarui di tempat: baris yang
  /// masih ada tetap memakai id-nya, supaya pesanan yang diubah di dua HP
  /// tidak dobel setelah sinkron (FR-10.4).
  Future<void> _replaceItems(String orderId, List<OrderItemInput> items) async {
    final old =
        await (_db.select(_db.orderItems)
              ..where((t) => t.orderId.equals(orderId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    final fresh = <OrderItemInput>[];
    for (final i in items) {
      final at = old.indexWhere((o) => o.productId == i.productId);
      if (at < 0) {
        fresh.add(i);
        continue;
      }
      final row = old.removeAt(at);
      if (row.qty != i.qty ||
          row.unitPrice != i.unitPrice ||
          row.note != i.note) {
        await (_db.update(
          _db.orderItems,
        )..where((t) => t.id.equals(row.id))).write(
          OrderItemsCompanion(
            qty: Value(i.qty),
            unitPrice: Value(i.unitPrice),
            lineTotal: Value(i.lineTotal),
            note: Value(i.note),
            updatedAt: Value(_now()),
          ),
        );
      }
    }
    for (final row in old) {
      await (_db.delete(
        _db.orderItems,
      )..where((t) => t.id.equals(row.id))).go();
    }
    await _writeItems(orderId, fresh);
  }

  Future<void> _replaceReminders(
    String orderId,
    DateTime dueAt,
    List<ReminderInput> reminders,
  ) async {
    final old =
        await (_db.select(_db.orderReminders)
              ..where((t) => t.orderId.equals(orderId))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    final fresh = <ReminderInput>[];
    for (final r in reminders) {
      final remindAt = r.remindAt(dueAt).toUtc();
      final at = old.indexWhere((o) => o.kind == r.kind);
      if (at < 0) {
        fresh.add(r);
        continue;
      }
      final row = old.removeAt(at);
      // Seperti pengingat baru: dijadwalkan lagi dari awal.
      if (!row.remindAt.isAtSameMomentAs(remindAt) ||
          row.status != ReminderStatus.scheduled) {
        await (_db.update(
          _db.orderReminders,
        )..where((t) => t.id.equals(row.id))).write(
          OrderRemindersCompanion(
            remindAt: Value(remindAt),
            status: const Value(ReminderStatus.scheduled),
            updatedAt: Value(_now()),
          ),
        );
      }
    }
    for (final row in old) {
      await (_db.delete(
        _db.orderReminders,
      )..where((t) => t.id.equals(row.id))).go();
    }
    await _writeReminders(orderId, dueAt, fresh);
  }

  Future<void> _writeReminders(
    String orderId,
    DateTime dueAt,
    List<ReminderInput> reminders,
  ) async {
    var next = await _nextNotificationId();
    for (final r in reminders) {
      await _db
          .into(_db.orderReminders)
          .insert(
            OrderRemindersCompanion.insert(
              orderId: orderId,
              kind: r.kind,
              remindAt: r.remindAt(dueAt).toUtc(),
              notificationId: next++,
            ),
          );
    }
  }

  /// Id notifikasi pengingat pesanan mulai 1000; di bawahnya untuk
  /// notifikasi tetap (ringkasan harian, Tutup hari, dll.).
  Future<int> _nextNotificationId() async {
    final max = _db.orderReminders.notificationId.max();
    final row = await (_db.selectOnly(
      _db.orderReminders,
    )..addColumns([max])).getSingle();
    final current = row.read(max) ?? 999;
    return current < 999 ? 1000 : current + 1;
  }

  Future<void> _cancelReminders(String orderId, {bool keepPayment = false}) =>
      (_db.update(_db.orderReminders)..where(
            (t) =>
                t.orderId.equals(orderId) &
                t.status.equalsValue(ReminderStatus.scheduled) &
                (keepPayment
                    ? t.kind.equalsValue(ReminderKind.payment).not()
                    : const Constant(true)),
          ))
          .write(
            OrderRemindersCompanion(
              status: const Value(ReminderStatus.cancelled),
              updatedAt: Value(_now()),
            ),
          );

  Future<void> _insertRefund(
    String orderId,
    int amount,
    PaymentMethod method,
  ) async => _db
      .into(_db.payments)
      .insert(
        PaymentsCompanion.insert(
          orderId: orderId,
          amount: amount,
          method: method,
          kind: PaymentKind.refund,
          paidAt: _now(),
          cashAccountId: Value(await _cashAccountFor(orderId, method)),
        ),
      );

  /// Akun kas penerima pembayaran pesanan (FR-15.2).
  Future<String> _cashAccountFor(String orderId, PaymentMethod method) async {
    final order = await (_db.select(
      _db.orders,
    )..where((t) => t.id.equals(orderId))).getSingle();
    return CashRepository(_db).accountFor(order.businessId, method);
  }

  /// Untuk sinkron: cache pembayaran dihitung ulang setelah pesanan atau
  /// pembayarannya ditarik dari HP lain (FR-10.3).
  Future<void> refreshPayment(String orderId) => _refreshPayment(orderId);

  /// Sisa tagihan dan status bayar dari semua pembayaran yang tidak dibatalkan.
  Future<void> _refreshPayment(String orderId) async {
    final order = await _order(orderId);
    final payments = await (_db.select(
      _db.payments,
    )..where((t) => t.orderId.equals(orderId) & t.voidedAt.isNull())).get();
    final paid = payments.fold(
      0,
      (sum, p) => sum + (p.kind == PaymentKind.refund ? -p.amount : p.amount),
    );
    await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
      OrdersCompanion(
        paidAmount: Value(paid),
        paymentStatus: Value(paymentStatusOf(paid: paid, total: order.total)),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<List<OrderView>> _views(
    List<Order> orders, {
    bool detail = false,
  }) async {
    if (orders.isEmpty) return const [];
    final ids = [for (final o in orders) o.id];
    final itemRows =
        await (_db.select(_db.orderItems).join([
                innerJoin(
                  _db.products,
                  _db.products.id.equalsExp(_db.orderItems.productId),
                ),
              ])
              ..where(_db.orderItems.orderId.isIn(ids))
              ..orderBy([OrderingTerm.asc(_db.orderItems.createdAt)]))
            .get();
    final lines = <String, List<OrderLine>>{};
    for (final row in itemRows) {
      final item = row.readTable(_db.orderItems);
      (lines[item.orderId] ??= []).add(
        OrderLine(item: item, product: row.readTable(_db.products)),
      );
    }
    final customerIds = {
      for (final o in orders)
        if (o.customerId != null) o.customerId!,
    };
    final customers = {
      for (final c in await (_db.select(
        _db.customers,
      )..where((t) => t.id.isIn(customerIds))).get())
        c.id: c,
    };
    final channels = {
      for (final c in await (_db.select(
        _db.salesChannels,
      )..where((t) => t.businessId.equals(orders.first.businessId))).get())
        c.id: c,
    };
    final payments = <String, List<Payment>>{};
    final reminders = <String, List<OrderReminder>>{};
    final productions = <String, List<Production>>{};
    if (detail) {
      for (final p
          in await (_db.select(_db.payments)
                ..where((t) => t.orderId.isIn(ids))
                ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
              .get()) {
        (payments[p.orderId] ??= []).add(p);
      }
      for (final r
          in await (_db.select(_db.orderReminders)
                ..where((t) => t.orderId.isIn(ids))
                ..orderBy([(t) => OrderingTerm.asc(t.remindAt)]))
              .get()) {
        (reminders[r.orderId] ??= []).add(r);
      }
      for (final p
          in await (_db.select(_db.productions)
                ..where((t) => t.orderId.isIn(ids))
                ..orderBy([(t) => OrderingTerm.asc(t.producedAt)]))
              .get()) {
        (productions[p.orderId!] ??= []).add(p);
      }
    }
    return [
      for (final o in orders)
        OrderView(
          order: o,
          lines: lines[o.id] ?? const [],
          customer: customers[o.customerId],
          channel: channels[o.channelId],
          payments: payments[o.id] ?? const [],
          reminders: reminders[o.id] ?? const [],
          productions: productions[o.id] ?? const [],
        ),
    ];
  }

  Future<Order> _order(String id) =>
      (_db.select(_db.orders)..where((t) => t.id.equals(id))).getSingle();

  Future<Business> _business(String id) =>
      (_db.select(_db.businesses)..where((t) => t.id.equals(id))).getSingle();

  Stream<T> _watch<T>(
    Future<T> Function() load, {
    List<TableInfo<Table, dynamic>> extra = const [],
  }) async* {
    yield await load();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        ...extra,
        _db.orders,
        _db.orderItems,
        _db.payments,
        _db.orderReminders,
        _db.customers,
        _db.salesChannels,
        _db.productions,
        _db.products,
        _db.ingredients,
      ]),
    )) {
      yield await load();
    }
  }
}
