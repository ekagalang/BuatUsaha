import 'package:flutter/services.dart';

String _group(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Nominal untuk diisi ke kolom Rupiah: 80000 → "80.000"; 0 → "".
String formatRupiahDigits(int amount) =>
    amount <= 0 ? '' : _group(amount.toString());

/// Titik ribuan muncul saat mengetik nominal Rupiah (80000 → 80.000); hasilnya
/// tetap dibaca `parseRupiahInput`. Kursor dijaga di antara angka yang sama.
class RupiahInputFormatter extends TextInputFormatter {
  const RupiahInputFormatter({this.maxDigits = 12});

  /// Batas digit supaya tetap muat di int (Rp999 miliar).
  final int maxDigits;

  static final _nonDigit = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(_nonDigit, '');
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > maxDigits) return oldValue;
    final formatted = _group(digits);
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsAfter = newValue.text
        .substring(cursor)
        .replaceAll(_nonDigit, '')
        .length;
    var offset = formatted.length;
    var seen = 0;
    while (offset > 0 && seen < digitsAfter) {
      offset--;
      if (formatted.codeUnitAt(offset) != 0x2E) seen++;
    }
    // Kursor tepat setelah angka yang diketik, bukan setelah titiknya.
    while (offset > 0 && formatted.codeUnitAt(offset - 1) == 0x2E) {
      offset--;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
