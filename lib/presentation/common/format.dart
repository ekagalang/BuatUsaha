import 'package:decimal/decimal.dart';

/// Format angka, uang, dan tanggal sesuai Design.md bagian 9.

const _minus = '−';

String _group(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Rp8.000, −Rp24.175.
String formatRupiah(int amount) =>
    '${amount < 0 ? _minus : ''}Rp${_group(amount.abs().toString())}';

/// 1.000, 1,5, 15,33 (koma desimal, titik ribuan, nol di belakang dibuang).
String formatDecimal(Decimal value, {int maxDecimals = 2}) {
  final rounded = value.round(scale: maxDecimals);
  final parts = rounded.abs().toString().split('.');
  var text = _group(parts[0]);
  if (parts.length > 1) {
    final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
    if (fraction.isNotEmpty) text += ',$fraction';
  }
  return rounded < Decimal.zero ? '$_minus$text' : text;
}

/// Rp15/g, Rp93,85/g; `null` = belum ada harga.
String formatUnitPrice(Decimal? price, String unit) =>
    price == null ? 'Belum ada harga' : 'Rp${formatDecimal(price)}/$unit';

/// 1.000 g, 1,5 butir.
String formatQty(Decimal qty, String unit) =>
    '${formatDecimal(qty, maxDecimals: 3)} $unit';

const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Senin, 19 Oktober 2026 (waktu lokal).
String formatLongDate(DateTime date) {
  final d = date.toLocal();
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// 19 Okt (waktu lokal).
String formatShortDate(DateTime date) {
  final d = date.toLocal();
  return '${d.day} ${_months[d.month - 1].substring(0, 3)}';
}

/// 16.00 (waktu lokal, 24 jam).
String formatTime(DateTime date) {
  final d = date.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
}

/// Membaca angka ketikan pengguna: "1,5" dan "1.000" (ribuan) sama-sama
/// dikenali; "1.5" dianggap desimal karena bukan pola ribuan.
Decimal? parseDecimalInput(String text) {
  var s = text.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final negative = s.startsWith('-') || s.startsWith(_minus);
  if (negative) s = s.substring(1);
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return null;
  final value = Decimal.parse(s);
  return negative ? -value : value;
}

/// Membaca nominal Rupiah: semua selain angka diabaikan ("Rp14.000" → 14000).
int? parseRupiahInput(String text) {
  final digits = text.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? null : int.parse(digits);
}
