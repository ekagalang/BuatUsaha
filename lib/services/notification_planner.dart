import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import '../data/repositories/day_close_repository.dart';
import '../data/repositories/order_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/stock_repository.dart';
import '../domain/orders/orders.dart';
import '../presentation/common/format.dart';
import 'notification_scheduler.dart';

/// Menyusun seluruh notifikasi lokal dari data terkini (FR-6.1–6.4, FR-6.8,
/// FR-6.9). Hasilnya selalu lengkap, jadi penjadwal cukup mengganti semua
/// jadwal lama dengan daftar ini setiap kali data berubah (FR-6.6).
class NotificationPlanner {
  NotificationPlanner(this._db)
    : _orders = _ordersFor(_db),
      _dayClose = DayCloseRepository(
        _db,
        ProductRepository(_db, StockRepository(_db)),
      );

  static OrderRepository _ordersFor(AppDatabase db) {
    final stock = StockRepository(db);
    return OrderRepository(db, stock, ProductRepository(db, stock));
  }

  final AppDatabase _db;
  final OrderRepository _orders;
  final DayCloseRepository _dayClose;

  /// Jadwal untuk [horizonDays] ke depan. Pengingat yang sudah lewat ditandai
  /// FIRED.
  Future<List<PlannedNotification>> plan({
    required DateTime now,
    int horizonDays = 14,
  }) async {
    final business = await (_db.select(
      _db.businesses,
    )..limit(1)).getSingleOrNull();
    if (business == null) return const [];
    final settings = await (_db.select(
      _db.notificationSettings,
    )..where((t) => t.businessId.equals(business.id))).getSingleOrNull();
    if (settings == null) return const [];
    final horizon = now.add(Duration(days: horizonDays));
    final result = <PlannedNotification>[];
    void add(PlannedNotification n) {
      final at = applyQuietHours(
        n.at,
        settings.quietStart,
        settings.quietEnd,
      ).toLocal();
      if (!at.isAfter(now) || at.isAfter(horizon)) return;
      result.add(
        PlannedNotification(
          id: n.id,
          at: at,
          title: n.title,
          body: n.body,
          payload: n.payload,
          channel: n.channel,
        ),
      );
    }

    await (_db.update(_db.orderReminders)..where(
          (t) =>
              t.status.equalsValue(ReminderStatus.scheduled) &
              t.remindAt.isSmallerOrEqualValue(now.toUtc()),
        ))
        .write(
          const OrderRemindersCompanion(status: Value(ReminderStatus.fired)),
        );

    final open = await _orders.listOrders(
      business.id,
      statuses: const [
        OrderStatus.newOrder,
        OrderStatus.inProgress,
        OrderStatus.ready,
      ],
      detail: true,
    );

    // Pengingat pesanan (FR-6.1).
    if (settings.orderEnabled) {
      for (final view in open) {
        for (final r in view.reminders) {
          if (r.status != ReminderStatus.scheduled ||
              r.kind == ReminderKind.payment) {
            continue;
          }
          add(
            PlannedNotification(
              id: r.notificationId,
              at: r.remindAt,
              title: 'Pesanan ${view.title} · ${formatTime(view.order.dueAt)}',
              body: '${_when(r.kind, view.order.dueAt)}: ${_summary(view)}',
              payload: 'order:${view.order.id}',
              channel: NotifyChannel.orders,
            ),
          );
        }
      }
    }

    final lowCount = await _lowStockCount(business.id);

    // Ringkasan harian (FR-6.2).
    if (settings.orderEnabled) {
      final (h, m) = parseClock(settings.dailySummaryTime);
      final local = now.toLocal();
      for (var i = 0; i < horizonDays; i++) {
        final day = DateTime(local.year, local.month, local.day + i);
        final at = DateTime(day.year, day.month, day.day, h, m);
        if (!at.isAfter(now)) continue;
        final due = await _orders.listOrders(
          business.id,
          from: day,
          to: day.add(const Duration(days: 1)),
        );
        final active = due
            .where((v) => v.order.status != OrderStatus.cancelled)
            .toList();
        final unpaid = active
            .where((v) => v.order.paymentStatus != PaymentStatus.paid)
            .length;
        if (active.isEmpty && lowCount == 0) continue;
        final parts = [
          active.isEmpty
              ? 'Hari ini belum ada pesanan'
              : 'Hari ini ${active.length} pesanan',
          if (unpaid > 0) '$unpaid belum lunas',
          if (lowCount > 0) '$lowCount bahan menipis',
        ];
        add(
          PlannedNotification(
            id: NotificationIds.summaryBase + i,
            at: at,
            title: 'Ringkasan ${formatLongDate(day)}',
            body: parts.join(', '),
            payload: 'home',
            channel: NotifyChannel.summary,
          ),
        );
      }
    }

    // Pengingat pelunasan (FR-6.4): pesanan Siap atau Selesai yang belum lunas,
    // diingatkan pukul 09.00 berikutnya.
    if (settings.paymentEnabled) {
      final since = now.subtract(const Duration(days: 30));
      final completed = await _orders.listOrders(
        business.id,
        completedFrom: since,
        statuses: const [OrderStatus.completed],
      );
      final unpaid = [
        ...open.where((v) => v.order.status == OrderStatus.ready),
        ...completed,
      ].where((v) => v.order.paymentStatus != PaymentStatus.paid);
      var i = 0;
      for (final view in unpaid) {
        final base = view.order.dueAt.isAfter(now) ? view.order.dueAt : now;
        final local = base.toLocal();
        var at = DateTime(local.year, local.month, local.day, 9);
        if (!at.isAfter(local)) at = at.add(const Duration(days: 1));
        add(
          PlannedNotification(
            id: NotificationIds.paymentBase + i++,
            at: at,
            title: 'Belum lunas: ${view.title}',
            body:
                '${view.order.orderNo} · sisa ${formatRupiah(view.remaining)} '
                'dari ${formatRupiah(view.order.total)}',
            payload: 'order:${view.order.id}',
            channel: NotifyChannel.payments,
          ),
        );
      }
    }

    // Pengingat Tutup hari (FR-6.9): hanya jika ada sisa dan hari ini belum
    // ditutup.
    if (settings.dayCloseEnabled &&
        !await _dayClose.isClosed(business.id, now)) {
      final leftovers = await _dayClose.leftovers(business.id, now);
      if (leftovers.isNotEmpty) {
        final (h, m) = parseClock(settings.dayCloseTime);
        final local = now.toLocal();
        final expired = leftovers
            .where((l) => l.expiredQty > Decimal.zero)
            .length;
        add(
          PlannedNotification(
            id: NotificationIds.dayClose,
            at: DateTime(local.year, local.month, local.day, h, m),
            title: 'Tutup hari',
            body:
                'Masih ada sisa ${leftovers.length} menu'
                '${expired > 0 ? ', $expired lewat umur simpan' : ''}. '
                'Catat yang disimpan dan dibuang.',
            payload: 'day-close',
            channel: NotifyChannel.dayClose,
          ),
        );
      }
    }

    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  /// Bahan yang baru turun di bawah minimum dan belum pernah diberi tahu
  /// (FR-6.3). Bahan yang dikembalikan ditandai sudah diberi tahu.
  Future<List<PlannedNotification>> takeLowStockAlerts({
    required DateTime now,
  }) async {
    final business = await (_db.select(
      _db.businesses,
    )..limit(1)).getSingleOrNull();
    if (business == null) return const [];
    final settings = await (_db.select(
      _db.notificationSettings,
    )..where((t) => t.businessId.equals(business.id))).getSingleOrNull();
    if (settings == null || !settings.stockEnabled) return const [];
    final rows =
        await (_db.select(_db.ingredients)..where(
              (t) =>
                  t.businessId.equals(business.id) &
                  t.deletedAt.isNull() &
                  t.lowStockNotified.equals(false) &
                  t.minStock.isBiggerThanValue(0),
            ))
            .get();
    final result = <PlannedNotification>[];
    for (final (i, ingredient) in rows.indexed) {
      final view = IngredientView(ingredient);
      if (!view.isLow) continue;
      final unit = ingredient.baseUnit.code;
      result.add(
        PlannedNotification(
          id: NotificationIds.lowStockBase + i,
          at: now,
          title: 'Stok ${ingredient.name} menipis',
          body:
              'Tinggal ${formatQty(view.stock, unit)}, di bawah minimum '
              '${formatQty(view.minStock, unit)}.',
          payload: 'ingredient:${ingredient.id}',
          channel: NotifyChannel.stock,
        ),
      );
      await (_db.update(_db.ingredients)
            ..where((t) => t.id.equals(ingredient.id)))
          .write(const IngredientsCompanion(lowStockNotified: Value(true)));
    }
    return result;
  }

  Future<int> _lowStockCount(String businessId) async {
    final rows =
        await (_db.select(_db.ingredients)..where(
              (t) =>
                  t.businessId.equals(businessId) &
                  t.deletedAt.isNull() &
                  t.minStock.isBiggerThanValue(0),
            ))
            .get();
    return rows.where((i) => IngredientView(i).isLow).length;
  }

  static String _when(ReminderKind kind, DateTime dueAt) => switch (kind) {
    ReminderKind.dayBefore => 'Besok ${formatShortDate(dueAt)}',
    ReminderKind.beforeDue => 'Jam ${formatTime(dueAt)}',
    _ => formatLongDate(dueAt),
  };

  static String _summary(OrderView view) {
    final items = [
      for (final l in view.lines) '${l.item.qty} ${l.product.name}',
    ].join(', ');
    final how = view.order.fulfillment == Fulfillment.delivery
        ? 'diantar'
        : 'diambil';
    final pay = view.order.paymentStatus == PaymentStatus.paid
        ? 'lunas'
        : 'sisa ${formatRupiah(view.remaining)}';
    return '$items · $how · $pay';
  }
}
