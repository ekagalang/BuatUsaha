import 'package:decimal/decimal.dart';

/// Jumlah desimal untuk harga per satuan dasar (mis. Rp15,333333/g).
const costScale = 6;

final hundred = Decimal.fromInt(100);

Decimal divide(Decimal a, Decimal b) =>
    (a / b).toDecimal(scaleOnInfinitePrecision: costScale);

Decimal rupiah(int amount) => Decimal.fromInt(amount);

/// Membulatkan ke Rupiah terdekat (setengah ke atas).
int toRupiah(Decimal value) => value.round().toBigInt().toInt();

/// Membulatkan ke atas ke kelipatan [step], mis. 7.736 → 8.000 untuk step 500.
int ceilToStep(Decimal value, int step) {
  if (step <= 0) throw ArgumentError.value(step, 'step', 'harus > 0');
  final steps = divide(value, Decimal.fromInt(step)).ceil();
  return steps.toBigInt().toInt() * step;
}
