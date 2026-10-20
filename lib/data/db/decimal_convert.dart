import 'package:decimal/decimal.dart';

/// Kolom REAL disimpan sebagai double; hitungan memakai Decimal.
/// Enam desimal cukup untuk takaran dan harga per satuan dasar.
Decimal dec(double value) => Decimal.parse(value.toStringAsFixed(6));

double dbl(Decimal value) => double.parse(value.toString());
