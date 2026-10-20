import 'dart:async';

import 'package:drift/drift.dart';

import '../data/db/app_database.dart';
import 'notification_planner.dart';
import 'notification_scheduler.dart';

/// Menjaga jadwal notifikasi selalu sesuai data: setiap perubahan pesanan,
/// pembayaran, stok, atau pengaturan memicu penjadwalan ulang (FR-6.6).
class NotificationSync {
  NotificationSync(this._db, this._scheduler, {DateTime Function()? clock})
    : _planner = NotificationPlanner(_db),
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final NotificationScheduler _scheduler;
  final NotificationPlanner _planner;
  final DateTime Function() _clock;
  StreamSubscription<void>? _sub;
  Timer? _debounce;
  var _running = false;
  var _again = false;

  void start() {
    _sub ??= _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.orders,
            _db.orderItems,
            _db.orderReminders,
            _db.payments,
            _db.ingredients,
            _db.products,
            _db.productStockMovements,
            _db.notificationSettings,
            _db.businesses,
          ]),
        )
        .listen((_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => resync());
  }

  Future<void> resync() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final now = _clock();
        final planned = await _planner.plan(now: now);
        await _scheduler.replaceScheduled(planned);
        for (final alert in await _planner.takeLowStockAlerts(now: now)) {
          await _scheduler.showNow(alert);
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _debounce?.cancel();
    await _sub?.cancel();
    _sub = null;
  }
}
