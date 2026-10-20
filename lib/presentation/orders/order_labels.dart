import '../../data/repositories/order_repository.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import '../common/widgets.dart';

/// Pill status pesanan; pesanan lewat jadwal tampil "Terlambat" (FR-5.3).
(String, StatusKind) orderStatusPill(OrderView view, DateTime now) {
  if (view.isLate(now)) return ('Terlambat', StatusKind.danger);
  return switch (view.order.status) {
    OrderStatus.newOrder => ('Baru', StatusKind.neutral),
    OrderStatus.inProgress => ('Diproses', StatusKind.warning),
    OrderStatus.ready => ('Siap', StatusKind.success),
    OrderStatus.completed => ('Selesai', StatusKind.success),
    OrderStatus.cancelled =>
      view.order.voidedAt != null
          ? ('Dikoreksi', StatusKind.danger)
          : ('Batal', StatusKind.danger),
  };
}

String statusLabel(OrderStatus status) => switch (status) {
  OrderStatus.newOrder => 'Baru',
  OrderStatus.inProgress => 'Diproses',
  OrderStatus.ready => 'Siap',
  OrderStatus.completed => 'Selesai',
  OrderStatus.cancelled => 'Batal',
};

String paymentLabel(OrderView view) => switch (view.order.paymentStatus) {
  PaymentStatus.paid => 'Lunas',
  PaymentStatus.partial =>
    'DP ${formatRupiah(view.order.paidAmount)}, sisa '
        '${formatRupiah(view.remaining)}',
  PaymentStatus.unpaid => 'Belum bayar',
};

String methodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Tunai',
  PaymentMethod.transfer => 'Transfer',
  PaymentMethod.qris => 'QRIS',
  PaymentMethod.other => 'Lainnya',
};

String paymentKindLabel(PaymentKind kind) => switch (kind) {
  PaymentKind.dp => 'DP',
  PaymentKind.settlement => 'Pelunasan',
  PaymentKind.refund => 'Uang kembali',
};

String fulfillmentLabel(Fulfillment f) => switch (f) {
  Fulfillment.pickup => 'Ambil',
  Fulfillment.delivery => 'Antar',
};

String reminderLabel(ReminderInput r) => switch (r.kind) {
  ReminderKind.dayBefore => 'H-1 pukul ${r.time!.replaceAll(':', '.')}',
  ReminderKind.beforeDue =>
    r.minutes! % 60 == 0
        ? '${r.minutes! ~/ 60} jam sebelum jadwal'
        : '${r.minutes} menit sebelum jadwal',
  _ => '${formatShortDate(r.at!)} ${formatTime(r.at!)}',
};

/// "10 brownies, 2 bolu pandan".
String itemsSummary(OrderView view) => [
  for (final l in view.lines) '${l.item.qty} ${l.product.name.toLowerCase()}',
].join(', ');

String channelName(OrderView view) => view.channel?.name ?? 'Langsung';
