import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/pricing_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../orders/order_labels.dart' show channelFeeText;
import '../theme.dart';

/// Kartu Harga per channel di Detail menu (FR-14.1, FR-14.2).
class ChannelPricesCard extends ConsumerWidget {
  const ChannelPricesCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(channelPriceRowsProvider(product.id)).value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SectionTitle('Harga per channel'),
            ),
            const SizedBox(height: 2),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Pesanan lewat channel otomatis memakai harga ini.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            for (final r in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.channel.name),
                subtitle: Text(
                  [
                    'potongan ${formatRupiah(toRupiah(r.feePerPcs))}',
                    if (r.profitPerPcs != null)
                      'laba ${formatRupiah(toRupiah(r.profitPerPcs!))}/pcs',
                  ].join(' · '),
                  style: TextStyle(
                    color: (r.profitPerPcs ?? Decimal.zero) < Decimal.zero
                        ? AppColors.danger
                        : AppColors.textMuted,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRupiah(r.price),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (r.customPrice == null)
                          const Text(
                            'harga utama',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _edit(context, ref, r),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ChannelPriceRow row,
  ) async {
    final result = await showAppDialog<_PriceResult>(
      context: context,
      builder: (_) => _ChannelPriceDialog(product: product, row: row),
    );
    if (result == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(pricingRepositoryProvider)
          .setChannelPrice(product.id, row.channel.id, price: result.price),
      result.price == null
          ? '${row.channel.name} memakai harga utama.'
          : 'Harga ${row.channel.name} disimpan.',
    );
  }
}

class _PriceResult {
  const _PriceResult(this.price);

  /// `null` = samakan dengan harga utama.
  final int? price;
}

class _ChannelPriceDialog extends StatefulWidget {
  const _ChannelPriceDialog({required this.product, required this.row});

  final Product product;
  final ChannelPriceRow row;

  @override
  State<_ChannelPriceDialog> createState() => _ChannelPriceDialogState();
}

class _ChannelPriceDialogState extends State<_ChannelPriceDialog> {
  late final _price = TextEditingController(
    text: formatRupiahDigits(widget.row.price),
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final suggestion = row.suggestion;
    final price = parseRupiahInput(_price.text);
    return AlertDialog(
      title: Text('Harga di ${row.channel.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _price,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [RupiahInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Harga per pcs',
              prefixText: 'Rp ',
              helperText:
                  'Harga utama ${formatRupiah(widget.product.sellingPrice)}',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 12),
            Text(
              'Saran ${formatRupiah(suggestion)}: laba per pcs sama dengan '
              'jual langsung setelah potongan ${channelFeeText(row.channel)}.',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(
                  () => _price.text = formatRupiahDigits(suggestion),
                ),
                child: const Text('Pakai saran'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (row.customPrice != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _PriceResult(null)),
            child: const Text('Samakan dengan harga utama'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: price == null || price <= 0
              ? null
              : () => Navigator.pop(
                  context,
                  _PriceResult(
                    price == widget.product.sellingPrice ? null : price,
                  ),
                ),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

String hppCauseLabel(ProductHppHistoryData h) => switch (h.cause) {
  HppChangeCause.created => 'Menu dibuat',
  HppChangeCause.recipe => 'Resep diubah',
  HppChangeCause.ingredientPrice =>
    h.note == null ? 'Harga bahan' : 'Harga ${h.note!.toLowerCase()}',
  HppChangeCause.wage => 'Upah pemilik',
};

/// Kartu Riwayat HPP di Detail menu (FR-14.3).
class HppHistoryCard extends ConsumerWidget {
  const HppHistoryCard({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(hppHistoryProvider(productId)).value;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    final points = rows.reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Riwayat HPP'),
            if (points.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(height: 140, child: _HppChart(points)),
            ],
            const SizedBox(height: 8),
            for (final h in rows.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.previousHpp == null
                                ? formatRupiah(toRupiah(dec(h.hppPerPcs)))
                                : '${formatRupiah(toRupiah(dec(h.previousHpp!)))} → '
                                      '${formatRupiah(toRupiah(dec(h.hppPerPcs)))}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: h.previousHpp == null
                                  ? AppColors.text
                                  : h.hppPerPcs > h.previousHpp!
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                          ),
                          Text(
                            hppCauseLabel(h),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${formatShortDate(h.changedAt)} ${formatTime(h.changedAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HppChart extends StatelessWidget {
  const _HppChart(this.points);

  /// Terlama dulu.
  final List<ProductHppHistoryData> points;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) p.hppPerPcs];
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final pad = high == low
        ? (high * 0.1).clamp(100, 1000)
        : (high - low) * 0.2;
    return LineChart(
      LineChartData(
        minY: (low - pad).clamp(0, double.infinity).toDouble(),
        maxY: (high + pad).toDouble(),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          bottomTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) {
                if (value != meta.min && value != meta.max) {
                  return const SizedBox.shrink();
                }
                return Text(
                  formatRupiah(value.round()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final (i, v) in values.indexed) FlSpot(i.toDouble(), v),
            ],
            color: AppColors.primary,
            barWidth: 2.5,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.primary,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
