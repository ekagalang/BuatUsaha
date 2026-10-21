import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

/// Pesanan selesai yang HPP-nya berubah setelah koreksi harga bahan; pengguna
/// memilih menghitung ulang per pesanan atau semuanya (FR-9.5, mockup
/// `KoreksiHPP`).
class CostCorrectionScreen extends ConsumerStatefulWidget {
  const CostCorrectionScreen({super.key});

  @override
  ConsumerState<CostCorrectionScreen> createState() =>
      _CostCorrectionScreenState();
}

class _CostCorrectionScreenState extends ConsumerState<CostCorrectionScreen> {
  var _busy = false;

  Future<void> _apply(List<OrderCorrection> list) async {
    setState(() => _busy = true);
    final repo = ref.read(orderRepositoryProvider);
    await runWithSnack(
      context,
      () async {
        for (final c in list) {
          await repo.applyCostCorrection(c.view.order.id);
        }
      },
      list.length == 1
          ? 'HPP pesanan dihitung ulang.'
          : 'HPP ${list.length} pesanan dihitung ulang.',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final corrections = ref.watch(costCorrectionsProvider);
    final list = corrections.value ?? const <OrderCorrection>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Koreksi HPP pesanan')),
      body: corrections.isLoading && list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                const Text(
                  'Harga bahan dikoreksi sesudah pesanan ini selesai. Pesanan '
                  'yang sudah selesai masih memakai HPP lama, jadi labanya '
                  'tercatat berbeda.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                _Hero(list: list),
                const SizedBox(height: 16),
                for (final c in list) ...[
                  _CorrectionCard(
                    correction: c,
                    onApply: _busy ? null : () => _apply([c]),
                  ),
                  const SizedBox(height: 10),
                ],
                const Text(
                  'Pesanan yang tidak dihitung ulang tetap memakai HPP saat '
                  'selesai; laporan tidak berubah sampai kamu memilih.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
      bottomNavigationBar: list.isEmpty
          ? null
          : BottomActionBar(
              child: FilledButton(
                onPressed: _busy ? null : () => _apply(list),
                child: Text('Hitung ulang semua (${list.length})'),
              ),
            ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.list});

  final List<OrderCorrection> list;

  @override
  Widget build(BuildContext context) {
    final oldTotal = list.fold(0, (s, c) => s + c.oldProfit);
    final newTotal = list.fold(0, (s, c) => s + c.newProfit);
    final delta = newTotal - oldTotal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            list.isEmpty
                ? 'Tidak ada pesanan yang perlu dihitung ulang'
                : 'Laba ${list.length} pesanan jika dihitung ulang',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onPrimaryMuted,
            ),
          ),
          if (list.isNotEmpty) ...[
            Text(
              '${delta >= 0 ? '+' : ''}${formatRupiah(delta)}',
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontSize: 30, color: AppColors.onPrimary),
            ),
            Text(
              'Tercatat ${formatRupiah(oldTotal)} → menjadi '
              '${formatRupiah(newTotal)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onPrimaryMuted,
              ),
            ),
          ] else
            const Text(
              'Laporan laba sudah memakai HPP terbaru.',
              style: TextStyle(fontSize: 15, color: AppColors.onPrimary),
            ),
        ],
      ),
    );
  }
}

class _CorrectionCard extends StatelessWidget {
  const _CorrectionCard({required this.correction, required this.onApply});

  final OrderCorrection correction;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final view = correction.view;
    final o = view.order;
    final delta = correction.profitDelta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              view.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              '${o.orderNo} · selesai ${formatShortDate(o.completedAt!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            for (final i in correction.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${i.line.item.qty} ${i.line.product.name.toLowerCase()}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'HPP ${formatRupiah(toRupiah(i.oldHpp))} → '
                        '${formatRupiah(toRupiah(i.newHpp))}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Laba',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text:
                          '${formatRupiah(correction.oldProfit)} → '
                          '${formatRupiah(correction.newProfit)} ',
                      children: [
                        TextSpan(
                          text:
                              '(${delta >= 0 ? '+' : ''}${formatRupiah(delta)})',
                          style: TextStyle(
                            color: delta >= 0
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onApply,
                child: const Text('Hitung ulang pesanan ini'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
