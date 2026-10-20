import 'package:decimal/decimal.dart';

import '../costing/money.dart';
import '../enums.dart';

/// Satu baris buku mutasi stok produk jadi, urut waktu kejadian.
class ProductLedgerMovement {
  const ProductLedgerMovement({
    required this.id,
    required this.type,
    required this.qty,
    required this.unitCost,
    this.reversalOfId,
  });

  final String id;
  final ProductMovementType type;

  /// Pcs; positif = masuk, negatif = keluar.
  final Decimal qty;

  /// HPP per pcs untuk barang masuk (stok awal, produksi).
  final Decimal unitCost;
  final String? reversalOfId;

  bool get isReceipt =>
      qty > Decimal.zero &&
      (type == ProductMovementType.production ||
          type == ProductMovementType.opening);
}

class ProductLedgerRow {
  const ProductLedgerRow({
    required this.unitCost,
    required this.value,
    required this.balanceAfter,
    required this.avgCostAfter,
    required this.cancelled,
  });

  final Decimal unitCost;
  final int value;
  final Decimal balanceAfter;
  final Decimal avgCostAfter;
  final bool cancelled;
}

class ProductLedgerResult {
  const ProductLedgerResult({
    required this.rows,
    required this.stock,
    required this.avgUnitCost,
  });

  final List<ProductLedgerRow> rows;
  final Decimal stock;
  final Decimal avgUnitCost;
}

/// Hitung ulang stok produk jadi (FR-4.5): produksi dan stok awal masuk
/// dengan HPP-nya (rata-rata tertimbang); terjual, dibuang, dan penyesuaian
/// keluar dengan HPP rata-rata saat itu. Baris yang dibatalkan beserta
/// pembaliknya dilewati.
ProductLedgerResult replayProductLedger(List<ProductLedgerMovement> movements) {
  final reversed = {
    for (final m in movements)
      if (m.reversalOfId != null) m.reversalOfId!,
  };
  var stock = Decimal.zero;
  var avg = Decimal.zero;
  final rows = <ProductLedgerRow>[];
  for (final m in movements) {
    final cancelled = m.reversalOfId != null || reversed.contains(m.id);
    var unitCost = avg;
    if (cancelled) {
      unitCost = m.unitCost;
    } else if (m.isReceipt) {
      avg = stock <= Decimal.zero
          ? m.unitCost
          : divide(stock * avg + m.qty * m.unitCost, stock + m.qty);
      stock += m.qty;
      unitCost = m.unitCost;
    } else {
      stock += m.qty;
    }
    rows.add(
      ProductLedgerRow(
        unitCost: unitCost,
        value: toRupiah(m.qty * unitCost),
        balanceAfter: stock,
        avgCostAfter: avg,
        cancelled: cancelled,
      ),
    );
  }
  return ProductLedgerResult(rows: rows, stock: stock, avgUnitCost: avg);
}
