/// Kanal notifikasi Android; pengguna bisa mengatur suaranya per kanal.
enum NotifyChannel {
  orders('orders', 'Pengingat pesanan'),
  summary('summary', 'Ringkasan harian'),
  stock('stock', 'Stok menipis'),
  payments('payments', 'Pengingat pelunasan'),
  dayClose('day_close', 'Tutup hari'),
  updates('updates', 'Pembaruan aplikasi');

  const NotifyChannel(this.id, this.label);

  final String id;
  final String label;
}

/// Satu notifikasi yang akan dijadwalkan atau langsung ditampilkan.
class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    required this.channel,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Tujuan saat diketuk (FR-6.5): `order:<id>`, `ingredient:<id>`,
  /// `day-close`, atau `home`.
  final String payload;
  final NotifyChannel channel;

  @override
  String toString() => '$id @ $at · $title · $body';
}

/// Penjadwal notifikasi lokal; diganti tiruan di test.
abstract class NotificationScheduler {
  /// Ganti seluruh jadwal yang tertunda dengan [notifications].
  Future<void> replaceScheduled(List<PlannedNotification> notifications);

  Future<void> showNow(PlannedNotification notification);
}

/// Id tetap untuk notifikasi yang tidak berasal dari baris pengingat.
abstract final class NotificationIds {
  /// Ringkasan harian hari ke-0..13.
  static const summaryBase = 1;
  static const dayClose = 50;

  /// Versi baru tersedia (FR-11.4).
  static const update = 60;

  /// Pengingat pelunasan per pesanan (urutan dalam satu sinkron).
  static const paymentBase = 500000;

  /// Stok menipis per bahan.
  static const lowStockBase = 700000;
}
