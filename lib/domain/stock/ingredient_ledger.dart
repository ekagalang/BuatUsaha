import 'package:decimal/decimal.dart';

import '../costing/money.dart';
import '../enums.dart';

/// Satu baris buku mutasi bahan, dalam bentuk yang dibutuhkan untuk hitung
/// ulang. Urutan daftar = urutan waktu kejadian.
class LedgerMovement {
  const LedgerMovement({
    required this.id,
    required this.type,
    required this.qtyBase,
    this.value = 0,
    this.unitCost,
    this.reversalOfId,
  });

  final String id;
  final MovementType type;

  /// Positif = masuk, negatif = keluar, 0 = harga perkiraan tanpa stok.
  final Decimal qtyBase;

  /// Nilai Rupiah tercatat. Untuk belanja dan stok awal = harga yang dibayar,
  /// dipakai apa adanya agar tidak ada selisih pembulatan.
  final int value;

  /// Harga per satuan untuk baris harga perkiraan (stok awal dengan qty 0).
  final Decimal? unitCost;

  /// Diisi pada mutasi pembalik (pembatalan).
  final String? reversalOfId;

  bool get isPricedReceipt =>
      qtyBase > Decimal.zero &&
      (type == MovementType.purchase || type == MovementType.opening);

  bool get isPriceEstimate =>
      type == MovementType.opening && qtyBase == Decimal.zero;
}

/// Saldo dan harga setelah satu baris.
class LedgerRowResult {
  const LedgerRowResult({
    required this.id,
    required this.unitCost,
    required this.value,
    required this.balanceAfter,
    required this.avgCostAfter,
    required this.cancelled,
  });

  final String id;
  final Decimal unitCost;
  final int value;
  final Decimal balanceAfter;
  final Decimal avgCostAfter;

  /// Baris yang dibatalkan atau mutasi pembaliknya; tidak memengaruhi saldo.
  final bool cancelled;
}

class LedgerResult {
  const LedgerResult({
    required this.rows,
    required this.stock,
    required this.avgUnitCost,
    required this.priceIsEstimate,
  });

  /// Sejajar dengan daftar mutasi masukan.
  final List<LedgerRowResult> rows;
  final Decimal stock;

  /// `null` = bahan belum punya harga.
  final Decimal? avgUnitCost;
  final bool priceIsEstimate;
}

/// Menghitung ulang seluruh buku mutasi satu bahan (FR-9.3).
///
/// - Belanja dan stok awal masuk dengan harganya sendiri (rata-rata
///   tertimbang); jika stok sebelumnya ≤ 0, harga baru = harga barang ini.
/// - Stok awal ber-qty 0 = harga perkiraan; dipakai hanya selama belum ada
///   harga dari belanja (FR-1.7).
/// - Mutasi lain (produksi, pesanan, rusak, penyesuaian, opname) memakai harga
///   rata-rata saat itu dan tidak mengubahnya.
/// - Baris yang dibatalkan beserta mutasi pembaliknya dilewati (FR-9.1).
LedgerResult replayIngredientLedger(List<LedgerMovement> movements) {
  final reversed = {
    for (final m in movements)
      if (m.reversalOfId != null) m.reversalOfId!,
  };
  var stock = Decimal.zero;
  Decimal? avg;
  var estimate = false;
  final rows = <LedgerRowResult>[];

  for (final m in movements) {
    final cancelled = m.reversalOfId != null || reversed.contains(m.id);
    var unitCost = avg ?? Decimal.zero;
    var value = 0;

    if (cancelled) {
      // Tidak mengubah saldo; nilai baris tetap ditampilkan apa adanya.
      value = m.value;
    } else if (m.isPricedReceipt) {
      final paid = rupiah(m.value);
      final currentAvg = avg;
      if (stock <= Decimal.zero || currentAvg == null || estimate) {
        avg = divide(paid, m.qtyBase);
      } else {
        avg = divide(stock * currentAvg + paid, stock + m.qtyBase);
      }
      stock += m.qtyBase;
      estimate = false;
      unitCost = divide(paid, m.qtyBase);
      value = m.value;
    } else if (m.isPriceEstimate) {
      final price = m.unitCost;
      if (price != null && (avg == null || estimate)) {
        avg = price;
        estimate = true;
      }
      unitCost = price ?? Decimal.zero;
    } else {
      stock += m.qtyBase;
      value = toRupiah(m.qtyBase * unitCost);
    }

    rows.add(
      LedgerRowResult(
        id: m.id,
        unitCost: unitCost,
        value: value,
        balanceAfter: stock,
        avgCostAfter: avg ?? Decimal.zero,
        cancelled: cancelled,
      ),
    );
  }

  return LedgerResult(
    rows: rows,
    stock: stock,
    avgUnitCost: avg,
    priceIsEstimate: estimate,
  );
}
