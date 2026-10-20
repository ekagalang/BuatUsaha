import 'package:decimal/decimal.dart';

import 'money.dart';

class StockValueLine {
  const StockValueLine({
    required this.ingredientId,
    required this.qty,
    required this.avgUnitCost,
  });

  final String ingredientId;
  final Decimal qty;

  /// `null` = bahan belum punya harga.
  final Decimal? avgUnitCost;

  /// Stok negatif dan bahan tanpa harga tidak bernilai.
  Decimal get value {
    final price = avgUnitCost;
    if (qty <= Decimal.zero || price == null) return Decimal.zero;
    return qty * price;
  }
}

/// Nilai modal sisa bahan atau stok produk jadi = Σ stok × harga rata-rata,
/// dibulatkan ke Rupiah.
int totalStockValue(Iterable<StockValueLine> lines) =>
    toRupiah(lines.fold(Decimal.zero, (sum, line) => sum + line.value));
