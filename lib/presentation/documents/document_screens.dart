import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/order_repository.dart';
import '../../services/update_controller.dart';
import '../theme.dart';
import 'pdf_documents.dart';
import 'receipt.dart';
import 'report_csv.dart';

/// Pratinjau PDF dengan tombol Bagikan dan Cetak (FR-13.3, FR-13.4).
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.load,
  });

  final String title;
  final String fileName;
  final Future<Uint8List> Function() load;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  late final Future<Uint8List> _pdf = widget.load();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async =>
                Printing.sharePdf(bytes: await _pdf, filename: widget.fileName),
          ),
          IconButton(
            tooltip: 'Cetak',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              final bytes = await _pdf;
              await Printing.layoutPdf(
                onLayout: (_) async => bytes,
                name: widget.fileName,
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _pdf,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Gagal membuat PDF: ${snapshot.error}'),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PdfPreview(
            build: (_) => bytes,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: widget.fileName,
            scrollViewDecoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
            ),
          );
        },
      ),
    );
  }
}

/// Nota PDF satu pesanan, ukuran dari Pengaturan.
class ReceiptPdfScreen extends ConsumerWidget {
  const ReceiptPdfScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(orderProvider(orderId)).value;
    final business = ref.watch(businessProvider).value;
    if (view == null || business == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nota')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return PdfPreviewScreen(
      title: 'Nota ${view.order.orderNo}',
      fileName: 'nota-${view.order.orderNo}.pdf',
      load: () async =>
          receiptPdf(Receipt.of(business, view), await PdfFonts.load()),
    );
  }
}

/// Ringkasan laporan periode `[from, to)` dalam PDF A4.
class ReportPdfScreen extends ConsumerWidget {
  const ReportPdfScreen({
    super.key,
    required this.from,
    required this.to,
    required this.label,
  });

  final DateTime from;
  final DateTime to;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider).value;
    if (business == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Laporan PDF')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return PdfPreviewScreen(
      title: 'Laporan PDF',
      fileName: 'laporan-${_slug(label)}.pdf',
      load: () async {
        final repo = ref.read(reportRepositoryProvider);
        return reportPdf(
          businessName: business.name,
          logo: decodeLogo(business.logoData),
          periodLabel: label,
          report: await repo.periodReport(business.id, from, to),
          data: await repo.exportData(business.id, from, to),
          fonts: await PdfFonts.load(),
          printedAt: DateTime.now(),
        );
      },
    );
  }
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `/laporan/pdf?dari=2026-10-01&sampai=2026-11-01&judul=Oktober 2026`.
String reportPdfPath(DateTime from, DateTime to, String label) => Uri(
  path: '/laporan/pdf',
  queryParameters: {'dari': _ymd(from), 'sampai': _ymd(to), 'judul': label},
).toString();

Widget reportPdfRoute(GoRouterState state) {
  final q = state.uri.queryParameters;
  final now = DateTime.now();
  final from =
      DateTime.tryParse(q['dari'] ?? '') ??
      DateTime(now.year, now.month, now.day);
  return ReportPdfScreen(
    from: from,
    to:
        DateTime.tryParse(q['sampai'] ?? '') ??
        from.add(const Duration(days: 1)),
    label: q['judul'] ?? '',
  );
}

Widget _sheet(List<Widget> children) => SafeArea(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  ),
);

/// Lembar Nota di Detail pesanan: WhatsApp, bagikan teks, PDF (FR-13.2).
Future<void> showReceiptSheet(
  BuildContext context,
  WidgetRef ref,
  OrderView view,
  Business business,
) async {
  final phone = waNumber(view.customer?.phoneWa);
  String text() => receiptText(Receipt.of(business, view));
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (sheetContext) {
      return _sheet([
        ListTile(
          enabled: phone != null,
          leading: const Icon(Icons.chat_outlined),
          title: const Text('Kirim ke WhatsApp pelanggan'),
          subtitle: Text(
            phone == null
                ? 'Pelanggan belum punya nomor WhatsApp'
                : view.customer!.phoneWa!,
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            ref.read(appPlatformProvider).openUrl(whatsappUrl(phone!, text()));
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('Bagikan teks nota'),
          onTap: () {
            Navigator.pop(sheetContext);
            SharePlus.instance.share(
              ShareParams(text: text(), subject: 'Nota ${view.order.orderNo}'),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Nota PDF'),
          subtitle: Text(
            '${business.receiptSize == ReceiptSize.roll58 ? 'Struk 58 mm' : 'A6'}'
            ' · ukuran diubah di Pengaturan',
          ),
          onTap: () {
            Navigator.pop(sheetContext);
            context.push('/pesanan/${view.order.id}/nota');
          },
        ),
      ]);
    },
  );
}

/// Lembar Ekspor di Laporan untuk periode `[from, to)` (FR-13.4).
Future<void> showReportExportSheet(
  BuildContext context,
  WidgetRef ref, {
  required DateTime from,
  required DateTime to,
  required String label,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (sheetContext) => _sheet([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Ekspor $label',
            style: Theme.of(sheetContext).textTheme.titleMedium,
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: const Text('Ringkasan PDF'),
        subtitle: const Text('Untung-rugi, per menu, per channel, pengeluaran'),
        onTap: () {
          Navigator.pop(sheetContext);
          context.push(reportPdfPath(from, to, label));
        },
      ),
      ListTile(
        leading: const Icon(Icons.table_chart_outlined),
        title: const Text('Data CSV'),
        subtitle: const Text(
          '4 file untuk Excel/Sheets: pesanan, item terjual, belanja, '
          'pengeluaran',
        ),
        onTap: () async {
          Navigator.pop(sheetContext);
          await shareReportCsv(ref, from, to, label);
        },
      ),
    ]),
  );
}

Future<void> shareReportCsv(
  WidgetRef ref,
  DateTime from,
  DateTime to,
  String label,
) async {
  final business = await ref.read(currentBusinessProvider.future);
  final data = await ref
      .read(reportRepositoryProvider)
      .exportData(business.id, from, to);
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (final csv in reportCsv(data, from, to)) {
    final file = File('${dir.path}/${csv.name}');
    await file.writeAsString(csv.content, flush: true);
    files.add(XFile(file.path, mimeType: 'text/csv', name: csv.name));
  }
  await SharePlus.instance.share(
    ShareParams(files: files, subject: 'Data ${business.name} $label'),
  );
}
