import 'package:decimal/decimal.dart';

import 'money.dart';

/// Harga jual = HPP × (1 + markup), dibulatkan ke atas ke kelipatan [rounding].
int suggestPriceByMarkup({
  required Decimal hppPerPcs,
  required Decimal markupPct,
  int rounding = 500,
}) {
  final price = divide(hppPerPcs * (hundred + markupPct), hundred);
  return ceilToStep(price, rounding);
}

/// Harga jual = HPP / (1 − margin), dibulatkan ke atas ke kelipatan [rounding].
int suggestPriceByMargin({
  required Decimal hppPerPcs,
  required Decimal marginPct,
  int rounding = 500,
}) {
  if (marginPct >= hundred) {
    throw ArgumentError.value(marginPct, 'marginPct', 'harus < 100');
  }
  final price = divide(hppPerPcs * hundred, hundred - marginPct);
  return ceilToStep(price, rounding);
}

/// Margin aktual dalam persen, 2 desimal: (harga − HPP) / harga × 100.
Decimal actualMarginPct({
  required int sellingPrice,
  required Decimal hppPerPcs,
}) {
  if (sellingPrice <= 0) {
    throw ArgumentError.value(sellingPrice, 'sellingPrice', 'harus > 0');
  }
  final price = rupiah(sellingPrice);
  return divide((price - hppPerPcs) * hundred, price).round(scale: 2);
}
