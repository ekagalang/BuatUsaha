import 'package:decimal/decimal.dart';

import '../../data/db/decimal_convert.dart';
import '../../data/repositories/report_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/enums.dart';

class CsvFile {
  const CsvFile(this.name, this.content);

  final String name;
  final String content;
}

/// Empat file CSV periode (FR-13.4): pemisah titik koma, desimal koma, UTF-8
/// dengan BOM, supaya langsung rapi di Excel berbahasa Indonesia dan Sheets.
List<CsvFile> reportCsv(ReportExport data, DateTime from, DateTime to) {
  final suffix =
      '${_date(from)}_${_date(to.subtract(const Duration(days: 1)))}';
  return [
    CsvFile(
      'pesanan-$suffix.csv',
      _csv(
        [
          'No pesanan',
          'Selesai',
          'Jenis',
          'Pelanggan',
          'Channel',
          'Subtotal',
          'Diskon',
          'Ongkir',
          'Total',
          'Potongan channel',
          'Dibayar',
          'Status bayar',
        ],
        [
          for (final e in data.orders)
            [
              e.order.orderNo,
              _dateTime(e.order.completedAt!),
              e.order.type == OrderType.direct ? 'Langsung' : 'Pesanan',
              e.customer ?? '',
              e.channel,
              e.order.subtotal,
              e.order.discount,
              e.order.shippingFee,
              e.order.total,
              e.order.channelFee,
              e.order.paidAmount,
              switch (e.order.paymentStatus) {
                PaymentStatus.paid => 'Lunas',
                PaymentStatus.partial => 'DP',
                PaymentStatus.unpaid => 'Belum bayar',
              },
            ],
        ],
      ),
    ),
    CsvFile(
      'item-terjual-$suffix.csv',
      _csv(
        [
          'No pesanan',
          'Selesai',
          'Menu',
          'Jumlah',
          'Harga satuan',
          'Omzet setelah diskon',
          'Potongan channel',
          'HPP',
          'Laba',
        ],
        [
          for (final s in data.sales)
            [
              s.orderNo,
              _dateTime(s.completedAt),
              s.product,
              s.qty,
              s.unitPrice,
              s.revenue,
              s.fee,
              toRupiah(s.cogs),
              toRupiah(s.profit),
            ],
        ],
      ),
    ),
    CsvFile(
      'belanja-$suffix.csv',
      _csv(
        [
          'Tanggal',
          'Pemasok',
          'Bahan',
          'Jumlah',
          'Satuan',
          'Total harga',
          'Catatan',
        ],
        [
          for (final p in data.purchases)
            [
              _dateTime(p.purchase.purchasedAt),
              p.supplier ?? '',
              p.ingredient,
              dec(p.item.qty),
              p.item.unitName,
              p.item.totalPrice,
              p.purchase.note ?? '',
            ],
        ],
      ),
    ),
    CsvFile(
      'pengeluaran-$suffix.csv',
      _csv(
        ['Tanggal', 'Kategori', 'Bulanan', 'Jumlah', 'Catatan'],
        [
          for (final e in data.expenses)
            [
              _dateTime(e.expense.spentAt),
              e.category.name,
              e.expense.isMonthly ? 'Ya' : 'Tidak',
              e.expense.amount,
              e.expense.note ?? '',
            ],
        ],
      ),
    ),
  ];
}

String _csv(List<String> header, List<List<Object?>> rows) {
  final b = StringBuffer('﻿')..write(header.map(_cell).join(';'));
  for (final r in rows) {
    b
      ..write('\r\n')
      ..write(r.map(_cell).join(';'));
  }
  return (b..write('\r\n')).toString();
}

String _cell(Object? value) {
  final text = switch (value) {
    null => '',
    Decimal d => d.round(scale: 3).toString().replaceFirst('.', ','),
    _ => value.toString(),
  };
  if (text.contains(RegExp('[;"\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)}';
}

String _dateTime(DateTime d) {
  final l = d.toLocal();
  return '${_date(l)} ${_two(l.hour)}:${_two(l.minute)}';
}
