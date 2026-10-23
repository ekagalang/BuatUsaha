import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/repositories/order_repository.dart';
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

/// Potongan channel ringkas: "20%", "Rp1.500/pcs", "20% + Rp2.000/pesanan";
/// kosong bila tanpa potongan (FR-20.5).
String channelFeeText(SalesChannel c) => [
  if (c.commissionPct > 0) '${formatDecimal(dec(c.commissionPct))}%',
  if (c.feePerPcs > 0) '${formatRupiah(c.feePerPcs)}/pcs',
  if (c.feePerOrder > 0) '${formatRupiah(c.feePerOrder)}/pesanan',
].join(' + ');

/// Label pilihan channel di form pesanan, mis. "GoFood · 20%".
String channelPillLabel(SalesChannel c) {
  final fee = channelFeeText(c);
  return fee.isEmpty ? c.name : '${c.name} · $fee';
}
