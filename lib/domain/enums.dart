/// Enum yang disimpan di database sebagai TEXT lewat [code].
///
/// Kode ditulis eksplisit agar data lama tetap terbaca walau nama enum di Dart
/// diganti, dan agar nilainya sama persis dengan kolom Postgres di fase 3.
abstract interface class CodedEnum {
  String get code;
}

enum IngredientCategory implements CodedEnum {
  raw('RAW'),
  packaging('PACKAGING'),
  other('OTHER');

  const IngredientCategory(this.code);
  @override
  final String code;
}

/// Satuan dasar bahan. Semua stok dan takaran resep disimpan dalam satuan ini.
enum BaseUnit implements CodedEnum {
  g('g'),
  ml('ml'),
  pcs('pcs');

  const BaseUnit(this.code);
  @override
  final String code;
}

enum StockDeductMode implements CodedEnum {
  onProduction('ON_PRODUCTION'),
  onComplete('ON_COMPLETE');

  const StockDeductMode(this.code);
  @override
  final String code;
}

/// Mutasi stok bahan.
enum MovementType implements CodedEnum {
  opening('OPENING'),
  purchase('PURCHASE'),
  production('PRODUCTION'),
  orderUsage('ORDER_USAGE'),
  adjustment('ADJUSTMENT'),
  waste('WASTE'),
  opname('OPNAME');

  const MovementType(this.code);
  @override
  final String code;
}

/// Mutasi stok produk jadi (produk ready stock).
enum ProductMovementType implements CodedEnum {
  opening('OPENING'),
  production('PRODUCTION'),
  sale('SALE'),
  waste('WASTE'),
  adjustment('ADJUSTMENT');

  const ProductMovementType(this.code);
  @override
  final String code;
}

/// Alasan produk jadi dibuang saat Tutup hari atau penyesuaian.
enum WasteReason implements CodedEnum {
  expired('EXPIRED'),
  damaged('DAMAGED'),
  selfUse('SELF_USE'),
  other('OTHER');

  const WasteReason(this.code);
  @override
  final String code;
}

/// Kelengkapan HPP: [estimated] = ada bahan dengan harga perkiraan,
/// [incomplete] = ada bahan yang belum punya harga sama sekali.
enum HppStatus implements CodedEnum {
  complete('COMPLETE'),
  estimated('ESTIMATED'),
  incomplete('INCOMPLETE');

  const HppStatus(this.code);
  @override
  final String code;
}

enum CostType implements CodedEnum {
  utilities('UTILITIES'),
  labor('LABOR'),
  depreciation('DEPRECIATION'),
  other('OTHER');

  const CostType(this.code);
  @override
  final String code;
}

enum CostBasis implements CodedEnum {
  perBatch('PER_BATCH'),
  perPcs('PER_PCS');

  const CostBasis(this.code);
  @override
  final String code;
}

enum OrderType implements CodedEnum {
  preOrder('PRE_ORDER'),
  direct('DIRECT');

  const OrderType(this.code);
  @override
  final String code;
}

enum OrderStatus implements CodedEnum {
  newOrder('NEW'),
  inProgress('IN_PROGRESS'),
  ready('READY'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const OrderStatus(this.code);
  @override
  final String code;
}

enum Fulfillment implements CodedEnum {
  pickup('PICKUP'),
  delivery('DELIVERY');

  const Fulfillment(this.code);
  @override
  final String code;
}

enum PaymentStatus implements CodedEnum {
  unpaid('UNPAID'),
  partial('PARTIAL'),
  paid('PAID');

  const PaymentStatus(this.code);
  @override
  final String code;
}

enum PaymentMethod implements CodedEnum {
  cash('CASH'),
  transfer('TRANSFER'),
  qris('QRIS'),
  other('OTHER');

  const PaymentMethod(this.code);
  @override
  final String code;
}

enum PaymentKind implements CodedEnum {
  dp('DP'),
  settlement('SETTLEMENT'),
  refund('REFUND');

  const PaymentKind(this.code);
  @override
  final String code;
}

enum ReminderKind implements CodedEnum {
  dayBefore('DAY_BEFORE'),
  beforeDue('BEFORE_DUE'),
  custom('CUSTOM'),
  payment('PAYMENT');

  const ReminderKind(this.code);
  @override
  final String code;
}

enum ReminderStatus implements CodedEnum {
  scheduled('SCHEDULED'),
  fired('FIRED'),
  cancelled('CANCELLED');

  const ReminderStatus(this.code);
  @override
  final String code;
}

/// Asal item daftar belanja (FR-12.5): dari hitungan pesanan, atau ditambah
/// atau diubah sendiri (tidak diubah Hitung ulang).
enum ShoppingItemSource implements CodedEnum {
  auto('AUTO'),
  manual('MANUAL');

  const ShoppingItemSource(this.code);
  @override
  final String code;
}

/// Ukuran nota PDF (FR-13.3).
enum ReceiptSize implements CodedEnum {
  a6('A6'),
  roll58('ROLL58');

  const ReceiptSize(this.code);
  @override
  final String code;
}
