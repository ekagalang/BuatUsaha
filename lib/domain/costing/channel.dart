import 'package:decimal/decimal.dart';

import 'money.dart';

/// Potongan channel = komisi % × total item (tanpa ongkir) + biaya per transaksi.
int channelFee({
  required int itemsTotal,
  required Decimal commissionPct,
  int feePerOrder = 0,
}) {
  if (itemsTotal < 0) {
    throw ArgumentError.value(itemsTotal, 'itemsTotal', 'harus ≥ 0');
  }
  return toRupiah(divide(rupiah(itemsTotal) * commissionPct, hundred)) +
      feePerOrder;
}

/// Membagi [amount] ke beberapa item sesuai porsi [weights] (mis. nilai tiap
/// item). Sisa pembulatan diberikan ke item bernilai terbesar, sehingga
/// jumlah hasilnya selalu sama dengan [amount].
List<int> allocateProportionally(int amount, List<int> weights) {
  if (amount < 0) {
    throw ArgumentError.value(amount, 'amount', 'harus ≥ 0');
  }
  final total = weights.fold(0, (sum, w) => sum + w);
  if (total <= 0) return List.filled(weights.length, 0);
  final shares = [for (final w in weights) amount * w ~/ total];
  var remainder = amount - shares.fold(0, (sum, s) => sum + s);
  final byWeight = List.generate(weights.length, (i) => i)
    ..sort((a, b) => weights[b].compareTo(weights[a]));
  for (var i = 0; remainder > 0; i = (i + 1) % byWeight.length) {
    shares[byWeight[i]]++;
    remainder--;
  }
  return shares;
}

/// Saran harga channel supaya laba per pcs sama dengan jual langsung
/// (FR-14.2): (harga langsung + biaya per pesanan ÷ rata-rata pcs per
/// pesanan) ÷ (1 − komisi), dibulatkan ke atas ke kelipatan [rounding].
/// `null` bila komisi ≥ 100%.
int? suggestChannelPrice({
  required int directPrice,
  required Decimal commissionPct,
  int feePerOrder = 0,
  required Decimal avgPcsPerOrder,
  int rounding = 500,
}) {
  if (commissionPct >= hundred || avgPcsPerOrder <= Decimal.zero) return null;
  final base =
      rupiah(directPrice) + divide(rupiah(feePerOrder), avgPcsPerOrder);
  return ceilToStep(divide(base * hundred, hundred - commissionPct), rounding);
}

/// Potongan channel per pcs pada harga [price]: komisi + biaya per pesanan
/// dibagi rata-rata pcs per pesanan.
Decimal channelFeePerPcs({
  required int price,
  required Decimal commissionPct,
  int feePerOrder = 0,
  required Decimal avgPcsPerOrder,
}) =>
    divide(rupiah(price) * commissionPct, hundred) +
    (avgPcsPerOrder <= Decimal.zero
        ? Decimal.zero
        : divide(rupiah(feePerOrder), avgPcsPerOrder));
