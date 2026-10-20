import 'package:decimal/decimal.dart';

enum ShelfStatus { fresh, expiresTomorrow, expired }

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Hari terakhir yang masih layak: diproduksi tanggal D dengan umur simpan
/// N hari → D + N − 1 (brownies 19 Okt, 3 hari → aman s.d. 21 Okt).
DateTime lastGoodDay(DateTime producedOn, int shelfLifeDays) {
  if (shelfLifeDays <= 0) {
    throw ArgumentError.value(shelfLifeDays, 'shelfLifeDays', 'harus > 0');
  }
  return _day(producedOn).add(Duration(days: shelfLifeDays - 1));
}

/// Status umur sisa produk pada tanggal [today] (FR-4.10).
ShelfStatus shelfStatus({
  required DateTime producedOn,
  required int shelfLifeDays,
  required DateTime today,
}) {
  final last = lastGoodDay(producedOn, shelfLifeDays);
  final t = _day(today);
  if (t.isAfter(last)) return ShelfStatus.expired;
  if (t == last) return ShelfStatus.expiresTomorrow;
  return ShelfStatus.fresh;
}

class ProductionBatch {
  const ProductionBatch({required this.producedOn, required this.qty});

  final DateTime producedOn;
  final Decimal qty;
}

/// Sisa stok per batch produksi, dengan anggapan batch paling lama terjual
/// lebih dulu. Anggapan ini hanya untuk umur simpan, bukan untuk harga.
/// Hasil diurutkan dari batch terbaru.
List<ProductionBatch> remainingBatches({
  required List<ProductionBatch> productions,
  required Decimal currentStock,
}) {
  final newestFirst = [...productions]
    ..sort((a, b) => b.producedOn.compareTo(a.producedOn));
  var left = currentStock;
  final result = <ProductionBatch>[];
  for (final batch in newestFirst) {
    if (left <= Decimal.zero) break;
    final take = batch.qty < left ? batch.qty : left;
    result.add(ProductionBatch(producedOn: batch.producedOn, qty: take));
    left -= take;
  }
  return result;
}
