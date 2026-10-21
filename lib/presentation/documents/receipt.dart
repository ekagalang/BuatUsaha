import 'dart:convert';
import 'dart:typed_data';

import '../../data/db/app_database.dart';
import '../../data/repositories/order_repository.dart';
import '../common/format.dart';

const defaultReceiptNote = 'Terima kasih sudah memesan.';

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.total,
  });

  final String name;
  final int qty;
  final int unitPrice;
  final int total;
}

/// Isi nota pesanan (FR-13.1), dipakai teks WhatsApp dan PDF.
class Receipt {
  const Receipt({
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.logo,
    this.paymentInfo,
    required this.footer,
    required this.size,
    required this.orderNo,
    required this.orderedAt,
    required this.dueAt,
    required this.direct,
    required this.fulfillment,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.shipping,
    required this.total,
    required this.paid,
    this.note,
  });

  factory Receipt.of(Business business, OrderView view) {
    final o = view.order;
    return Receipt(
      businessName: business.name,
      businessAddress: _blank(business.address),
      businessPhone: _blank(business.phoneWa),
      logo: decodeLogo(business.logoData),
      paymentInfo: _blank(business.paymentInfo),
      footer: _blank(business.receiptNote) ?? defaultReceiptNote,
      size: business.receiptSize,
      orderNo: o.orderNo,
      orderedAt: o.createdAt,
      dueAt: o.dueAt,
      direct: o.type == OrderType.direct,
      fulfillment: o.fulfillment,
      customerName: view.customer?.name,
      customerPhone: _blank(view.customer?.phoneWa),
      deliveryAddress: o.fulfillment == Fulfillment.delivery
          ? _blank(o.deliveryAddress)
          : null,
      lines: [
        for (final l in view.lines)
          ReceiptLine(
            name: l.product.name,
            qty: l.item.qty,
            unitPrice: l.item.unitPrice,
            total: l.item.lineTotal,
          ),
      ],
      subtotal: o.subtotal,
      discount: o.discount,
      shipping: o.shippingFee,
      total: o.total,
      paid: o.paidAmount,
      note: _blank(o.note),
    );
  }

  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final Uint8List? logo;
  final String? paymentInfo;
  final String footer;
  final ReceiptSize size;
  final String orderNo;
  final DateTime orderedAt;
  final DateTime dueAt;
  final bool direct;
  final Fulfillment fulfillment;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final List<ReceiptLine> lines;
  final int subtotal;
  final int discount;
  final int shipping;
  final int total;
  final int paid;
  final String? note;

  int get remaining => total - paid;
  bool get settled => remaining <= 0;

  /// "Ambil: Kamis, 23 Oktober 2026 13.00"; penjualan langsung → tanggalnya.
  String get scheduleLine => direct
      ? 'Tanggal: ${formatLongDate(dueAt)} ${formatTime(dueAt)}'
      : '${fulfillment == Fulfillment.pickup ? 'Ambil' : 'Kirim'}: '
            '${formatLongDate(dueAt)} ${formatTime(dueAt)}';

  String get orderedLine =>
      'Dipesan: ${formatLongDate(orderedAt)} ${formatTime(orderedAt)}';

  String lineDetail(ReceiptLine l) => '${l.qty} × ${formatRupiah(l.unitPrice)}';

  /// Label dan nilai ringkasan; diskon dan ongkir hanya bila ada.
  List<(String, String)> get totals => [
    ('Subtotal', formatRupiah(subtotal)),
    if (discount > 0) ('Diskon', formatRupiah(-discount)),
    if (shipping > 0) ('Ongkir', formatRupiah(shipping)),
  ];

  List<(String, String)> get payments => [
    if (paid > 0 && !settled) ('Sudah dibayar', formatRupiah(paid)),
    if (!settled) ('Sisa', formatRupiah(remaining)),
  ];
}

String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

Uint8List? decodeLogo(String? data) {
  if (data == null || data.isEmpty) return null;
  try {
    return base64Decode(data);
  } on FormatException {
    return null;
  }
}

/// Teks nota untuk WhatsApp (tebal pakai `*`).
String receiptText(Receipt r) {
  final b = StringBuffer()
    ..writeln('*${r.businessName}*')
    ..writeln('Nota ${r.orderNo}');
  if (!r.direct) b.writeln(r.orderedLine);
  b.writeln(r.scheduleLine);
  if (r.customerName != null) b.writeln('Pelanggan: ${r.customerName}');
  if (r.deliveryAddress != null) b.writeln('Alamat: ${r.deliveryAddress}');
  b.writeln();
  for (final l in r.lines) {
    b.writeln('${l.name}  ${r.lineDetail(l)} = ${formatRupiah(l.total)}');
  }
  b.writeln();
  for (final (label, value) in r.totals) {
    b.writeln('$label: $value');
  }
  b.writeln('*Total: ${formatRupiah(r.total)}*');
  if (r.settled) {
    b.writeln('*LUNAS*');
  } else {
    final payments = r.payments;
    for (final (i, (label, value)) in payments.indexed) {
      b.writeln(
        i == payments.length - 1 ? '*$label: $value*' : '$label: $value',
      );
    }
  }
  if (!r.settled && r.paymentInfo != null) {
    b
      ..writeln()
      ..writeln('Pembayaran:')
      ..writeln(r.paymentInfo);
  }
  if (r.note != null) {
    b
      ..writeln()
      ..writeln('Catatan: ${r.note}');
  }
  b
    ..writeln()
    ..write(r.footer);
  return b.toString();
}

/// Nomor WhatsApp untuk wa.me: angka saja, 08… → 628…; `null` bila kosong.
String? waNumber(String? phone) {
  if (phone == null) return null;
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.startsWith('0')) {
    digits = '62${digits.substring(1)}';
  } else if (digits.startsWith('8')) {
    digits = '62$digits';
  }
  return digits;
}

String whatsappUrl(String number, String text) =>
    'https://wa.me/$number?text=${Uri.encodeComponent(text)}';
