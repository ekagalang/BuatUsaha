import '../enums.dart';

/// Status bayar dari jumlah yang sudah dibayar (FR-5.2).
PaymentStatus paymentStatusOf({required int paid, required int total}) {
  if (paid <= 0) return PaymentStatus.unpaid;
  return paid >= total ? PaymentStatus.paid : PaymentStatus.partial;
}

/// Pesanan lewat jadwal yang belum Selesai/Batal ditandai Terlambat (FR-5.3).
bool isOrderLate(OrderStatus status, DateTime dueAt, DateTime now) =>
    (status == OrderStatus.newOrder ||
        status == OrderStatus.inProgress ||
        status == OrderStatus.ready) &&
    dueAt.isBefore(now);

/// Status berikutnya di alur Baru → Diproses → Siap → Selesai.
OrderStatus? nextStatus(OrderStatus status) => switch (status) {
  OrderStatus.newOrder => OrderStatus.inProgress,
  OrderStatus.inProgress => OrderStatus.ready,
  OrderStatus.ready => OrderStatus.completed,
  OrderStatus.completed || OrderStatus.cancelled => null,
};

String _two(int n) => n.toString().padLeft(2, '0');

/// `PO-261020-001` (pesanan) atau `JL-261020-001` (penjualan langsung);
/// tanggal memakai waktu lokal.
String orderNumber(OrderType type, DateTime date, int sequence) {
  final d = date.toLocal();
  final prefix = type == OrderType.preOrder ? 'PO' : 'JL';
  return '$prefix-${_two(d.year % 100)}${_two(d.month)}${_two(d.day)}-'
      '${sequence.toString().padLeft(3, '0')}';
}

/// "08:00" → (8, 0).
(int, int) parseClock(String hhmm) {
  final parts = hhmm.split(':');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

/// Jam tenang (FR-6.8): pengingat yang jatuh di antara [start] dan [end]
/// (waktu lokal, boleh melewati tengah malam) digeser ke [end].
DateTime applyQuietHours(DateTime at, String? start, String? end) {
  if (start == null || end == null || start == end) return at;
  final local = at.toLocal();
  final (sh, sm) = parseClock(start);
  final (eh, em) = parseClock(end);
  final minutes = local.hour * 60 + local.minute;
  final s = sh * 60 + sm;
  final e = eh * 60 + em;
  final inQuiet = s < e
      ? minutes >= s && minutes < e
      : minutes >= s || minutes < e;
  if (!inQuiet) return at;
  var shifted = DateTime(local.year, local.month, local.day, eh, em);
  if (!shifted.isAfter(local)) shifted = shifted.add(const Duration(days: 1));
  return shifted;
}

/// Waktu pengingat dari jenisnya (FR-6.1): H-1 pada jam tertentu, atau
/// sekian menit sebelum jadwal.
DateTime reminderTime(
  ReminderKind kind,
  DateTime dueAt, {
  String? time,
  int? minutes,
  DateTime? at,
}) {
  final due = dueAt.toLocal();
  switch (kind) {
    case ReminderKind.dayBefore:
      final (h, m) = parseClock(time ?? '08:00');
      return DateTime(due.year, due.month, due.day - 1, h, m);
    case ReminderKind.beforeDue:
      return due.subtract(Duration(minutes: minutes ?? 120));
    case ReminderKind.custom:
    case ReminderKind.payment:
      return (at ?? due).toLocal();
  }
}
