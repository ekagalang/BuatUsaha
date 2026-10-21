import 'package:drift/drift.dart';

import '../../../domain/enums.dart';
import 'business_tables.dart';
import 'common.dart';
import 'product_tables.dart';

class Customers extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get phoneWa => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get note => text().nullable()();
}

/// Channel penjualan (Langsung, WhatsApp, GoFood, ...) dan potongannya.
class SalesChannels extends Table with EntityColumns {
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get name => text()();

  /// Komisi % dari total item (tanpa ongkir).
  RealColumn get commissionPct => real().withDefault(const Constant(0.0))();

  /// Biaya tetap per transaksi.
  IntColumn get feePerOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

/// Pesanan dan penjualan langsung. Omzet diakui saat status COMPLETED.
@TableIndex(name: 'orders_business_due', columns: {#businessId, #dueAt})
@TableIndex(name: 'orders_business_status', columns: {#businessId, #status})
@TableIndex(
  name: 'orders_business_completed',
  columns: {#businessId, #completedAt},
)
class Orders extends Table with EntityColumns, VoidColumns {
  TextColumn get businessId => text().references(Businesses, #id)();

  /// mis. `PO-261019-001`, unik per usaha.
  TextColumn get orderNo => text()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();

  /// Kosong = Langsung.
  TextColumn get channelId =>
      text().nullable().references(SalesChannels, #id)();
  TextColumn get type =>
      text().map(const CodedEnumConverter(OrderType.values))();
  TextColumn get status => text()
      .map(const CodedEnumConverter(OrderStatus.values))
      .withDefault(const Constant('NEW'))();

  /// Tanggal + jam ambil/kirim.
  DateTimeColumn get dueAt => dateTime()();
  TextColumn get fulfillment => text()
      .map(const CodedEnumConverter(Fulfillment.values))
      .withDefault(const Constant('PICKUP'))();
  TextColumn get deliveryAddress => text().nullable()();

  /// total = subtotal − discount + shippingFee. Ongkir bukan omzet.
  IntColumn get subtotal => integer()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get shippingFee => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();

  /// Potongan channel pesanan ini; otomatis dari channel, bisa diubah.
  IntColumn get channelFee => integer().withDefault(const Constant(0))();

  /// Cache jumlah [Payments].
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get paymentStatus => text()
      .map(const CodedEnumConverter(PaymentStatus.values))
      .withDefault(const Constant('UNPAID'))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {businessId, orderNo},
  ];
}

class OrderItems extends Table with EntityColumns {
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get lineTotal => integer()();

  /// Diisi saat pesanan selesai agar laba historis tidak ikut berubah.
  RealColumn get hppPerPcsSnapshot => real().nullable()();

  /// Status HPP saat terjual; laporan memberi tanda jika bukan COMPLETE.
  TextColumn get hppStatusSnapshot =>
      text().nullable().map(const CodedEnumConverter(HppStatus.values))();
  TextColumn get note => text().nullable()();
}

class Payments extends Table with EntityColumns, VoidColumns {
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  IntColumn get amount => integer()();
  TextColumn get method =>
      text().map(const CodedEnumConverter(PaymentMethod.values))();
  TextColumn get kind =>
      text().map(const CodedEnumConverter(PaymentKind.values))();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get note => text().nullable()();

  /// Akun kas penerima (FR-15.2), dari pemetaan cara bayar saat dicatat;
  /// kosong untuk data sebelum skema v6.
  TextColumn get cashAccountId => text().nullable()();
}

@TableIndex(name: 'order_reminders_status_time', columns: {#status, #remindAt})
class OrderReminders extends Table with EntityColumns {
  TextColumn get orderId =>
      text().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind =>
      text().map(const CodedEnumConverter(ReminderKind.values))();
  DateTimeColumn get remindAt => dateTime()();

  /// Id di flutter_local_notifications, dipakai untuk membatalkan jadwal.
  IntColumn get notificationId => integer()();
  TextColumn get status => text()
      .map(const CodedEnumConverter(ReminderStatus.values))
      .withDefault(const Constant('SCHEDULED'))();
}
