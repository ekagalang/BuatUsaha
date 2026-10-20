import 'package:decimal/decimal.dart';

import 'money.dart';

/// Saldo stok satu bahan (satuan dasar) atau satu menu jadi (pcs) beserta
/// harga rata-ratanya.
class StockLevel {
  const StockLevel({required this.qty, required this.avgUnitCost});

  static final empty = StockLevel(qty: Decimal.zero, avgUnitCost: Decimal.zero);

  final Decimal qty;

  /// Rp per satuan dasar (bahan) atau HPP per pcs (produk jadi).
  final Decimal avgUnitCost;
}

/// Qty dalam satuan beli → satuan dasar, mis. 1 kg × 1000 = 1000 g.
Decimal toBaseQty(Decimal qty, Decimal factorToBase) => qty * factorToBase;

/// Harga per satuan dasar dari satu baris belanja.
Decimal unitCostOf({required Decimal qtyBase, required int totalPrice}) {
  if (qtyBase <= Decimal.zero) {
    throw ArgumentError.value(qtyBase, 'qtyBase', 'harus > 0');
  }
  return divide(rupiah(totalPrice), qtyBase);
}

/// Stok masuk senilai [totalValue]; harga rata-rata tertimbang diperbarui.
///
/// Jika stok sebelumnya ≤ 0, harga rata-rata baru = harga barang yang masuk.
StockLevel applyReceiptValue(
  StockLevel current, {
  required Decimal qty,
  required Decimal totalValue,
}) {
  if (qty <= Decimal.zero) {
    throw ArgumentError.value(qty, 'qty', 'harus > 0');
  }
  final newQty = current.qty + qty;
  if (current.qty <= Decimal.zero) {
    return StockLevel(qty: newQty, avgUnitCost: divide(totalValue, qty));
  }
  final value = current.qty * current.avgUnitCost + totalValue;
  return StockLevel(qty: newQty, avgUnitCost: divide(value, newQty));
}

/// Stok masuk dari belanja bahan.
StockLevel applyPurchase(
  StockLevel current, {
  required Decimal qtyBase,
  required int totalPrice,
}) => applyReceiptValue(current, qty: qtyBase, totalValue: rupiah(totalPrice));

/// Stok masuk dengan harga per unit: stok awal, atau hasil produksi yang masuk
/// ke stok produk jadi dengan HPP batch-nya.
StockLevel applyReceipt(
  StockLevel current, {
  required Decimal qty,
  required Decimal unitCost,
}) => applyReceiptValue(current, qty: qty, totalValue: qty * unitCost);

/// Stok keluar (produksi, pesanan, terjual, dibuang); harga rata-rata tetap.
StockLevel applyIssue(StockLevel current, {required Decimal qtyBase}) {
  if (qtyBase < Decimal.zero) {
    throw ArgumentError.value(qtyBase, 'qtyBase', 'harus ≥ 0');
  }
  return StockLevel(
    qty: current.qty - qtyBase,
    avgUnitCost: current.avgUnitCost,
  );
}

/// Satu baris buku mutasi untuk dihitung ulang.
class LedgerEntry {
  /// Barang masuk senilai [totalValue] (belanja, stok awal, hasil produksi).
  LedgerEntry.receipt({required this.qty, required Decimal this.totalValue}) {
    if (qty <= Decimal.zero) {
      throw ArgumentError.value(qty, 'qty', 'harus > 0');
    }
  }

  /// Barang keluar sebanyak [qty] pada harga rata-rata saat itu.
  LedgerEntry.issue({required this.qty}) : totalValue = null {
    if (qty < Decimal.zero) {
      throw ArgumentError.value(qty, 'qty', 'harus ≥ 0');
    }
  }

  final Decimal qty;

  /// `null` untuk barang keluar.
  final Decimal? totalValue;
}

/// Menghitung ulang saldo dan harga rata-rata dari awal (FR-9.3), dipakai
/// setelah transaksi dibatalkan, diedit, atau dicatat dengan tanggal mundur.
///
/// [entries] harus sudah urut menurut waktu kejadian, dan transaksi yang
/// dibatalkan beserta mutasi pembaliknya sudah dikeluarkan. Hasilnya saldo
/// setelah tiap baris, sejajar dengan [entries].
List<StockLevel> replayLedger(
  Iterable<LedgerEntry> entries, {
  StockLevel? start,
}) {
  var level = start ?? StockLevel.empty;
  final result = <StockLevel>[];
  for (final entry in entries) {
    final value = entry.totalValue;
    level = value == null
        ? applyIssue(level, qtyBase: entry.qty)
        : applyReceiptValue(level, qty: entry.qty, totalValue: value);
    result.add(level);
  }
  return result;
}
