import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/report_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../documents/document_screens.dart';
import '../orders/order_form_screen.dart' show SummaryRow;
import '../theme.dart';

enum Period { day, week, month, range }

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `[from, to)` untuk periode yang memuat [anchor].
(DateTime, DateTime) periodRange(Period period, DateTime anchor) {
  final d = _dayOnly(anchor);
  return switch (period) {
    Period.day => (d, d.add(const Duration(days: 1))),
    Period.week => () {
      final monday = d.subtract(Duration(days: d.weekday - 1));
      return (monday, monday.add(const Duration(days: 7)));
    }(),
    Period.month => (DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
    Period.range => (d, d.add(const Duration(days: 1))),
  };
}

/// Tab Laporan: ringkasan harian per menu (FR-7.6) dan laporan periode
/// (FR-7.5, FR-7.8). Mockup `Laporan`.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  var _period = Period.day;
  var _anchor = _dayOnly(DateTime.now());
  DateTimeRange? _custom;

  (DateTime, DateTime) get _range {
    if (_period == Period.range && _custom != null) {
      return (_custom!.start, _custom!.end.add(const Duration(days: 1)));
    }
    return periodRange(_period, _anchor);
  }

  void _shift(int step) => setState(() {
    _anchor = switch (_period) {
      Period.day => _anchor.add(Duration(days: step)),
      Period.week => _anchor.add(Duration(days: 7 * step)),
      Period.month => DateTime(_anchor.year, _anchor.month + step),
      Period.range => _anchor,
    };
  });

  Future<void> _pick() async {
    final now = DateTime.now();
    if (_period == Period.range) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _custom,
      );
      if (picked != null) setState(() => _custom = picked);
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _anchor = picked);
  }

  String get _label {
    final (from, to) = _range;
    final last = to.subtract(const Duration(days: 1));
    return switch (_period) {
      Period.day => formatLongDate(from),
      Period.month => formatLongDate(from).split(' ').skip(2).join(' '),
      _ => '${formatShortDate(from)} – ${formatShortDate(last)} ${last.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(
            tooltip: 'Kas',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => context.push('/laporan/kas'),
          ),
          IconButton(
            tooltip: 'Ekspor',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => showReportExportSheet(
              context,
              ref,
              from: range.$1,
              to: range.$2,
              label: _label,
            ),
          ),
          TextButton.icon(
            onPressed: () => context.push('/laporan/pengeluaran'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Pengeluaran'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Segmented(
            labels: const ['Hari', 'Minggu', 'Bulan', 'Rentang'],
            selected: _period.index,
            onSelected: (i) => setState(() {
              _period = Period.values[i];
              if (_period == Period.range && _custom == null) {
                final (from, to) = periodRange(Period.week, _anchor);
                _custom = DateTimeRange(
                  start: from,
                  end: to.subtract(const Duration(days: 1)),
                );
              }
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_period != Period.range)
                IconButton(
                  tooltip: 'Sebelumnya',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
              Expanded(
                child: TextButton(
                  onPressed: _pick,
                  child: Text(
                    _label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (_period != Period.range)
                IconButton(
                  tooltip: 'Berikutnya',
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_period == Period.day)
            _DayView(day: range.$1)
          else
            _PeriodView(range: range, monthly: _period == Period.month),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({
    required this.title,
    required this.net,
    required this.caption,
  });

  final String title;
  final int net;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = net > 0
        ? ('Untung', StatusKind.success)
        : net < 0
        ? ('Rugi', StatusKind.danger)
        : ('Impas', StatusKind.neutral);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimaryMuted,
                  ),
                ),
              ),
              StatusPill(label, kind: kind),
            ],
          ),
          Text(
            formatRupiah(net),
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontSize: 34, color: AppColors.onPrimary),
          ),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onPrimaryMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dayReportProvider(day));
    final channels = ref.watch(
      periodReportProvider((day, day.add(const Duration(days: 1)))),
    );
    return report.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Gagal memuat laporan: $e'),
      data: (r) {
        final s = r.summary;
        final isToday = _dayOnly(DateTime.now()) == day;
        final pressing = r.mostPressuring;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHero(
              title: isToday ? 'Status hari ini' : 'Status hari itu',
              net: s.netProfit,
              caption: 'Laba bersih',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SummaryRow('Omzet', formatRupiah(s.revenue)),
                    SummaryRow('Potongan channel', formatRupiah(-s.channelFee)),
                    SummaryRow('HPP terjual', formatRupiah(-s.cogs)),
                    SummaryRow(
                      'Rugi sisa (dibuang)',
                      formatRupiah(-s.wasteLoss),
                    ),
                    SummaryRow(
                      'Laba menu',
                      formatRupiah(s.menuProfit),
                      bold: true,
                    ),
                    if (s.materialLoss != 0)
                      SummaryRow(
                        'Rugi bahan (rusak, opname)',
                        formatRupiah(-s.materialLoss),
                      ),
                    SummaryRow(
                      'Pengeluaran hari ini'
                      '${r.expenses.isEmpty ? '' : ' (${r.expenses.map((e) => e.expense.note ?? e.category.name.toLowerCase()).join(', ')})'}',
                      formatRupiah(-s.expenses),
                    ),
                    SummaryRow(
                      'Laba bersih',
                      formatRupiah(s.netProfit),
                      bold: true,
                      color: s.netProfit >= 0
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Per menu'),
            const SizedBox(height: 8),
            if (r.products.isEmpty)
              const Text(
                'Belum ada produksi atau penjualan di tanggal ini.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            for (final p in r.products) ...[
              _ProductDayCard(
                p,
                pressing: pressing?.product.id == p.product.id,
              ),
              const SizedBox(height: 8),
            ],
            if (pressing != null && pressing.wasteLoss > Decimal.zero)
              InfoBox(
                'Paling menekan laba: ${pressing.product.name}, '
                '${formatDecimal(pressing.discarded)} pcs dibuang '
                '(${formatRupiah(toRupiah(pressing.wasteLoss))}).',
              ),
            const SizedBox(height: 16),
            const SectionTitle('Per channel'),
            const SizedBox(height: 8),
            channels.maybeWhen(
              data: (p) => _ChannelList(rows: p.channels),
              orElse: () => const SizedBox.shrink(),
            ),
            if (isToday) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.nights_stay_outlined),
                  title: Text(
                    r.closed
                        ? 'Tutup hari sudah dicatat'
                        : 'Tutup hari belum dicatat',
                  ),
                  subtitle: Text(
                    r.closed
                        ? 'Ketuk untuk mencatat sisa lain yang dibuang'
                        : 'Catat sisa menu yang disimpan dan dibuang',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tutup-hari'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ProductDayCard extends StatelessWidget {
  const _ProductDayCard(this.p, {required this.pressing});

  final ProductDayReport p;
  final bool pressing;

  @override
  Widget build(BuildContext context) {
    final left = [
      if (p.discarded > Decimal.zero) '${formatDecimal(p.discarded)} dibuang',
      if (p.kept > Decimal.zero) '${formatDecimal(p.kept)} disimpan',
    ];
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return Card(
      shape: pressing
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.dangerStrong),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.product.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (p.hasIncompleteHpp)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: StatusPill(
                      'HPP belum lengkap',
                      kind: StatusKind.warning,
                    ),
                  ),
                Text(
                  formatRupiah(toRupiah(p.profit)),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: p.profit >= Decimal.zero
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                stat('Dibuat', formatDecimal(p.made)),
                stat('Terjual', '${p.sold}'),
                stat('Sisa', left.isEmpty ? '0' : left.join(', ')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                stat('Omzet', formatRupiah(p.revenue)),
                stat('HPP terjual', formatRupiah(-toRupiah(p.cogs))),
                stat('Rugi sisa', formatRupiah(-toRupiah(p.wasteLoss))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({required this.rows});

  final List<ChannelRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text(
        'Belum ada penjualan.',
        style: TextStyle(color: AppColors.textMuted),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (i, c) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              title: Text(c.name),
              subtitle: Text(
                '${c.orders} transaksi · omzet ${formatRupiah(c.revenue)} · '
                'potongan ${formatRupiah(c.fee)}',
              ),
              trailing: Text(
                formatRupiah(toRupiah(c.profit)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodView extends ConsumerWidget {
  const _PeriodView({required this.range, required this.monthly});

  final (DateTime, DateTime) range;
  final bool monthly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(periodReportProvider(range));
    return report.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Gagal memuat laporan: $e'),
      data: (r) {
        final margin = r.marginPct;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHero(
              title: 'Laba bersih periode',
              net: r.netProfit,
              caption: '${r.orders} transaksi selesai',
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SummaryRow('Omzet', formatRupiah(r.revenue)),
                    SummaryRow('Potongan channel', formatRupiah(-r.channelFee)),
                    SummaryRow('HPP terjual', formatRupiah(-r.cogs)),
                    SummaryRow(
                      'Laba kotor${margin == null ? '' : ' (margin ${formatDecimal(margin, maxDecimals: 1)}%)'}',
                      formatRupiah(r.grossProfit),
                      bold: true,
                    ),
                    SummaryRow(
                      'Rugi produk dibuang',
                      formatRupiah(-r.productLoss),
                    ),
                    SummaryRow('Rugi bahan', formatRupiah(-r.materialLoss)),
                    SummaryRow(
                      monthly
                          ? 'Pengeluaran (termasuk bulanan)'
                          : 'Pengeluaran',
                      formatRupiah(-r.expenses),
                    ),
                    SummaryRow(
                      'Laba bersih',
                      formatRupiah(r.netProfit),
                      bold: true,
                      color: r.netProfit >= 0
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    if (r.shipping > 0)
                      SummaryRow(
                        'Ongkir ditagih (bukan omzet)',
                        formatRupiah(r.shipping),
                      ),
                  ],
                ),
              ),
            ),
            if (r.incompleteHppItems > 0) ...[
              const SizedBox(height: 8),
              InfoBox(
                '${r.incompleteHppItems} item terjual dengan HPP belum lengkap; '
                'laba sebenarnya bisa lebih kecil.',
              ),
            ],
            const SizedBox(height: 16),
            const SectionTitle('Tren laba harian'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: SizedBox(height: 180, child: _TrendChart(r.trend)),
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Menu terlaris'),
            const SizedBox(height: 8),
            _RankList(
              ranks: r.bestSellers.take(5).toList(),
              value: (p) => '${p.qty} pcs',
            ),
            const SizedBox(height: 16),
            const SectionTitle('Paling menguntungkan'),
            const SizedBox(height: 8),
            _RankList(
              ranks: r.mostProfitable.take(5).toList(),
              value: (p) => formatRupiah(toRupiah(p.profit)),
            ),
            const SizedBox(height: 16),
            const SectionTitle('Per channel'),
            const SizedBox(height: 8),
            _ChannelList(rows: r.channels),
            if (!monthly) ...[
              const SizedBox(height: 12),
              const Text(
                'Pengeluaran bulanan seperti sewa hanya dihitung penuh di '
                'tampilan bulanan.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({required this.ranks, required this.value});

  final List<ProductRank> ranks;
  final String Function(ProductRank) value;

  @override
  Widget build(BuildContext context) {
    if (ranks.isEmpty) {
      return const Text(
        'Belum ada penjualan.',
        style: TextStyle(color: AppColors.textMuted),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (i, r) in ranks.indexed)
            ListTile(
              dense: true,
              leading: Text(
                '${i + 1}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              title: Text(r.product.name),
              trailing: Text(
                value(r),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart(this.points);

  final List<DayPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.every((p) => p.profit == 0)) {
      return const Center(
        child: Text(
          'Belum ada transaksi di periode ini.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    final step = (points.length / 6).ceil().clamp(1, 31);
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length || i % step != 0) {
                  return const SizedBox.shrink();
                }
                return Text(
                  '${points[i].day.day}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final (i, p) in points.indexed)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: p.profit.toDouble(),
                  width: points.length > 15 ? 6 : 14,
                  color: p.profit >= 0
                      ? AppColors.accentWarm
                      : AppColors.dangerStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
