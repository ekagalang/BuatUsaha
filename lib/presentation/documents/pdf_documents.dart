import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/repositories/report_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import 'receipt.dart';

/// Plus Jakarta Sans yang dibundel, supaya Rp, ×, −, dan · tampil benar.
class PdfFonts {
  const PdfFonts(this.regular, this.bold);

  final pw.Font regular;
  final pw.Font bold;

  static Future<PdfFonts> load() async => PdfFonts(
    pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'),
    ),
    pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf')),
  );
}

const _mm = PdfPageFormat.mm;
const _ink = PdfColor.fromInt(0xFF2B1D14);
const _muted = PdfColor.fromInt(0xFF6F5E52);
const _line = PdfColor.fromInt(0xFFDCCBB6);
const _brand = PdfColor.fromInt(0xFF6B3E26);
const _tint = PdfColor.fromInt(0xFFF1E2CF);

class _Style {
  const _Style(this.fonts, this.size);

  final PdfFonts fonts;
  final double size;

  pw.Widget text(
    String s, {
    bool bold = false,
    double? size,
    PdfColor color = _ink,
    pw.TextAlign? align,
  }) => pw.Text(
    s,
    textAlign: align,
    style: pw.TextStyle(
      font: bold ? fonts.bold : fonts.regular,
      fontSize: size ?? this.size,
      color: color,
    ),
  );

  pw.Widget row(
    String label,
    String value, {
    bool bold = false,
    double? size,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: text(label, bold: bold, size: size),
        ),
        pw.SizedBox(width: 6),
        text(value, bold: bold, size: size),
      ],
    ),
  );

  pw.Widget get divider =>
      pw.Divider(thickness: 0.6, color: _line, height: size * 1.6);
}

/// Nota pesanan PDF ukuran A6 atau struk 58 mm (FR-13.3).
Future<Uint8List> receiptPdf(Receipt r, PdfFonts fonts) {
  final roll = r.size == ReceiptSize.roll58;
  final s = _Style(fonts, roll ? 7 : 8.5);
  final center = roll
      ? pw.CrossAxisAlignment.center
      : pw.CrossAxisAlignment.start;
  final align = roll ? pw.TextAlign.center : pw.TextAlign.left;

  final header = <pw.Widget>[
    if (r.logo != null)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Image(pw.MemoryImage(r.logo!), height: roll ? 26 : 30),
      ),
    s.text(r.businessName, bold: true, size: s.size + 4, align: align),
    if (r.businessAddress != null)
      s.text(r.businessAddress!, color: _muted, align: align),
    if (r.businessPhone != null)
      s.text('WhatsApp ${r.businessPhone}', color: _muted, align: align),
  ];

  final content = <pw.Widget>[
    pw.Column(crossAxisAlignment: center, children: header),
    s.divider,
    s.row('Nota', r.orderNo, bold: true),
    if (!r.direct) s.text(r.orderedLine, color: _muted),
    s.text(r.scheduleLine, color: _muted),
    if (r.customerName != null) s.text('Pelanggan: ${r.customerName}'),
    if (r.customerPhone != null)
      s.text('WhatsApp ${r.customerPhone}', color: _muted),
    if (r.deliveryAddress != null) s.text('Alamat: ${r.deliveryAddress}'),
    s.divider,
    for (final l in r.lines)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            s.text(l.name, bold: true),
            s.row(r.lineDetail(l), formatRupiah(l.total)),
          ],
        ),
      ),
    s.divider,
    for (final (label, value) in r.totals) s.row(label, value),
    s.row('Total', formatRupiah(r.total), bold: true, size: s.size + 2),
    if (r.settled)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _brand, width: 0.8),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: s.text('LUNAS', bold: true, color: _brand),
        ),
      )
    else
      for (final (i, (label, value)) in r.payments.indexed)
        s.row(label, value, bold: i == r.payments.length - 1),
    if (!r.settled && r.paymentInfo != null) ...[
      pw.SizedBox(height: 6),
      pw.Container(
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          color: _tint,
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [s.text('Pembayaran', bold: true), s.text(r.paymentInfo!)],
        ),
      ),
    ],
    if (r.note != null) ...[
      pw.SizedBox(height: 6),
      s.text('Catatan: ${r.note}', color: _muted),
    ],
    s.divider,
    s.text(r.footer, align: pw.TextAlign.center),
  ];

  final doc = pw.Document(title: 'Nota ${r.orderNo}', author: r.businessName);
  if (roll) {
    // Tinggi tak terbatas: halaman mengikuti panjang isi.
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          58 * _mm,
          double.infinity,
          marginAll: 3 * _mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
    );
  } else {
    doc.addPage(
      pw.MultiPage(
        pageFormat: const PdfPageFormat(
          105 * _mm,
          148 * _mm,
          marginAll: 8 * _mm,
        ),
        build: (_) => content,
      ),
    );
  }
  return doc.save();
}

/// Ringkasan laporan periode A4 (FR-13.4).
Future<Uint8List> reportPdf({
  required String businessName,
  Uint8List? logo,
  required String periodLabel,
  required PeriodReport report,
  required ReportExport data,
  required PdfFonts fonts,
  required DateTime printedAt,
}) {
  final r = report;
  final s = _Style(fonts, 9.5);
  final margin = r.marginPct;

  pw.Widget section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: s.text(title, bold: true, size: 12, color: _brand),
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Set<int> numeric = const {},
  }) {
    if (rows.isEmpty) return s.text('Tidak ada data.', color: _muted);
    final alignments = {
      for (var i = 0; i < headers.length; i++)
        i: numeric.contains(i)
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
    };
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: null,
      headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9, color: _ink),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9, color: _ink),
      headerDecoration: const pw.BoxDecoration(color: _tint),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
      ),
      headerAlignments: alignments,
      cellAlignments: alignments,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );
  }

  final products = [...r.products]
    ..sort((a, b) => b.revenue.compareTo(a.revenue));
  final content = <pw.Widget>[
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 10),
            child: pw.Image(pw.MemoryImage(logo), height: 40),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              s.text(businessName, bold: true, size: 16),
              s.text('Laporan untung-rugi · $periodLabel', color: _muted),
            ],
          ),
        ),
        s.text(
          'Dibuat ${formatShortDate(printedAt)} ${printedAt.year} '
          '${formatTime(printedAt)}',
          color: _muted,
          size: 8,
        ),
      ],
    ),
    section('Ringkasan'),
    s.row('Transaksi selesai', '${r.orders}'),
    s.row('Omzet', formatRupiah(r.revenue)),
    s.row('Potongan channel', formatRupiah(-r.channelFee)),
    s.row('HPP terjual', formatRupiah(-r.cogs)),
    s.row(
      'Laba kotor${margin == null ? '' : ' (margin ${formatDecimal(margin, maxDecimals: 1)}%)'}',
      formatRupiah(r.grossProfit),
      bold: true,
    ),
    s.row('Rugi produk dibuang', formatRupiah(-r.productLoss)),
    s.row('Rugi bahan', formatRupiah(-r.materialLoss)),
    s.row('Pengeluaran', formatRupiah(-r.expenses)),
    s.row('Laba bersih', formatRupiah(r.netProfit), bold: true, size: 11),
    if (r.shipping > 0)
      s.row('Ongkir ditagih (bukan omzet)', formatRupiah(r.shipping)),
    if (r.incompleteHppItems > 0)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: s.text(
          '${r.incompleteHppItems} item terjual dengan HPP belum lengkap; '
          'laba sebenarnya bisa lebih kecil.',
          color: _muted,
        ),
      ),
    section('Per menu'),
    table(
      ['Menu', 'Terjual', 'Omzet', 'Laba'],
      [
        for (final p in products)
          [
            p.product.name,
            '${p.qty} pcs',
            formatRupiah(p.revenue),
            formatRupiah(toRupiah(p.profit)),
          ],
      ],
      numeric: {1, 2, 3},
    ),
    section('Per channel'),
    table(
      ['Channel', 'Transaksi', 'Omzet', 'Potongan', 'Laba'],
      [
        for (final c in r.channels)
          [
            c.name,
            '${c.orders}',
            formatRupiah(c.revenue),
            formatRupiah(-c.fee),
            formatRupiah(toRupiah(c.profit)),
          ],
      ],
      numeric: {1, 2, 3, 4},
    ),
    section('Pengeluaran'),
    table(
      ['Tanggal', 'Kategori', 'Catatan', 'Jumlah'],
      [
        for (final e in data.expenses)
          [
            '${formatShortDate(e.expense.spentAt)} ${e.expense.spentAt.toLocal().year}',
            e.category.name,
            e.expense.note ?? '',
            formatRupiah(e.expense.amount),
          ],
      ],
      numeric: {3},
    ),
  ];

  final doc = pw.Document(
    title: 'Laporan $businessName $periodLabel',
    author: businessName,
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 16 * _mm,
        marginRight: 16 * _mm,
        marginTop: 14 * _mm,
        marginBottom: 14 * _mm,
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: s.text(
          'Halaman ${context.pageNumber} dari ${context.pagesCount}',
          color: _muted,
          size: 8,
        ),
      ),
      build: (_) => content,
    ),
  );
  return doc.save();
}
