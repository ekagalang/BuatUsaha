import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/presentation/common/format.dart';
import 'package:buat_usaha/presentation/common/rupiah_input.dart';

TextEditingValue _type(String old, String typed, {int? cursor}) =>
    const RupiahInputFormatter().formatEditUpdate(
      TextEditingValue(text: old),
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: cursor ?? typed.length),
      ),
    );

void main() {
  test('titik ribuan muncul saat mengetik', () {
    expect(_type('8.00', '8.000').text, '8.000');
    expect(_type('8.000', '8.0000').text, '80.000');
    expect(_type('', '140000').text, '140.000');
    expect(_type('80.000', '80.000').selection.baseOffset, 6);
  });

  test('menghapus dan nol di depan', () {
    expect(_type('80.000', '80.00').text, '8.000');
    expect(_type('1', '').text, '');
    expect(_type('', '0050').text, '50');
    expect(_type('', 'Rp 1.500').text, '1.500');
  });

  test('kursor tetap di antara angka yang sama saat menyisip di tengah', () {
    // 1.000 → sisip "5" setelah angka 1 → 15.000, kursor setelah "5".
    final v = _type('1.000', '15.000', cursor: 2);
    expect(v.text, '15.000');
    expect(v.selection.baseOffset, 2);
  });

  test('hasilnya tetap dibaca parseRupiahInput dan dibatasi 12 digit', () {
    expect(parseRupiahInput(_type('', '1234567').text), 1234567);
    expect(formatRupiahDigits(8000), '8.000');
    expect(formatRupiahDigits(0), '');
    expect(_type('999.999.999.999', '9999999999999').text, '999.999.999.999');
  });
}
