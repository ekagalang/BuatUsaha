import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hpp_app/presentation/common/format.dart';

Decimal d(String value) => Decimal.parse(value);

void main() {
  test('Rupiah tanpa spasi, titik ribuan, minus asli', () {
    expect(formatRupiah(82950), 'Rp82.950');
    expect(formatRupiah(-24175), '−Rp24.175');
    expect(formatRupiah(0), 'Rp0');
  });

  test('desimal dengan koma, nol di belakang dibuang', () {
    expect(formatDecimal(d('15.333333')), '15,33');
    expect(formatDecimal(d('1000')), '1.000');
    expect(formatDecimal(d('1.50')), '1,5');
    expect(formatUnitPrice(d('93.846153'), 'g'), 'Rp93,85/g');
    expect(formatUnitPrice(null, 'g'), 'Belum ada harga');
    expect(formatQty(d('-50'), 'g'), '−50 g');
  });

  test('tanggal dan jam bahasa Indonesia', () {
    final date = DateTime(2026, 10, 19, 16, 5);
    expect(formatLongDate(date), 'Senin, 19 Oktober 2026');
    expect(formatShortDate(date), '19 Okt');
    expect(formatTime(date), '16.05');
  });

  test('membaca angka ketikan pengguna', () {
    expect(parseDecimalInput('1,5'), d('1.5'));
    expect(parseDecimalInput('1.000'), d('1000'));
    expect(parseDecimalInput('1.5'), d('1.5'));
    expect(parseDecimalInput('1.000,25'), d('1000.25'));
    expect(parseDecimalInput('abc'), isNull);
    expect(parseDecimalInput(''), isNull);
    expect(parseRupiahInput('Rp14.000'), 14000);
    expect(parseRupiahInput(''), isNull);
  });
}
