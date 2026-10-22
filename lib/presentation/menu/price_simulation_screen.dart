import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/pricing_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../layout.dart';
import '../theme.dart';

/// Simulasi kenaikan harga bahan (FR-14.4): HPP, laba, dan saran harga baru
/// per menu terdampak. Tidak menyimpan apa pun.
class PriceSimulationScreen extends ConsumerStatefulWidget {
  const PriceSimulationScreen({super.key});

  @override
  ConsumerState<PriceSimulationScreen> createState() =>
      _PriceSimulationScreenState();
}

class _PriceSimulationScreenState extends ConsumerState<PriceSimulationScreen> {
  var _byPercent = true;
  final _inputs = <String, TextEditingController>{};
  Future<List<SimulationRow>>? _result;

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rp per satuan dasar yang baru; bahan tanpa isian atau tanpa harga
  /// (mode persen) dilewati.
  Map<String, Decimal> _newCosts(Map<String, IngredientView> byId) {
    final costs = <String, Decimal>{};
    for (final MapEntry(key: id, value: c) in _inputs.entries) {
      final value = parseDecimalInput(c.text);
      final current = byId[id]?.avgUnitCost;
      if (value == null) continue;
      if (_byPercent) {
        if (current == null) continue;
        final next = current * (hundred + value) / hundred;
        costs[id] = next.toDecimal(scaleOnInfinitePrecision: costScale);
      } else if (value >= Decimal.zero) {
        costs[id] = value;
      }
    }
    return costs;
  }

  void _recompute(Map<String, IngredientView> byId) {
    final business = ref.read(businessProvider).value;
    if (business == null) return;
    final costs = _newCosts(byId);
    setState(() {
      _result = costs.isEmpty
          ? null
          : ref.read(pricingRepositoryProvider).simulate(business.id, costs);
    });
  }

  Future<void> _add(List<IngredientView> ingredients) async {
    final picked = await showModalBottomSheet<IngredientView>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          children: [
            for (final i in ingredients)
              if (!_inputs.containsKey(i.ingredient.id))
                ListTile(
                  title: Text(i.ingredient.name),
                  subtitle: Text(
                    formatUnitPrice(i.avgUnitCost, i.ingredient.unitLabel),
                  ),
                  onTap: () => Navigator.pop(context, i),
                ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _inputs[picked.ingredient.id] = TextEditingController());
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    ref.watch(businessProvider);
    final byId = {for (final i in ingredients) i.ingredient.id: i};
    return Scaffold(
      appBar: AppBar(title: const Text('Simulasi harga bahan')),
      body: ListView(
        padding: readablePadding(
          context,
          const EdgeInsets.fromLTRB(20, 4, 20, 24),
        ),
        children: [
          const InfoBox(
            'Coba kalau harga bahan naik atau turun: HPP dan saran harga '
            'menu dihitung ulang. Simulasi tidak menyimpan apa pun.',
          ),
          const SizedBox(height: 16),
          Segmented(
            labels: const ['Naik/turun %', 'Harga baru'],
            selected: _byPercent ? 0 : 1,
            onSelected: (i) {
              _byPercent = i == 0;
              for (final c in _inputs.values) {
                c.clear();
              }
              _recompute(byId);
            },
          ),
          const SizedBox(height: 12),
          for (final MapEntry(key: id, value: controller) in _inputs.entries)
            if (byId[id] case final view?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                view.ingredient.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Sekarang ${formatUnitPrice(view.avgUnitCost, view.ingredient.unitLabel)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: controller,
                            enabled: !_byPercent || view.avgUnitCost != null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _byPercent ? 'Naik' : 'Harga baru',
                              suffixText: _byPercent
                                  ? '%'
                                  : '/${view.ingredient.unitLabel}',
                              prefixText: _byPercent ? null : 'Rp',
                            ),
                            onChanged: (_) => _recompute(byId),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus ${view.ingredient.name}',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _inputs.remove(id)?.dispose();
                            _recompute(byId);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _add([
                for (final v in ingredients)
                  if (!v.isArchived) v,
              ]),
              icon: const Icon(Icons.add),
              label: const Text('Tambah bahan'),
            ),
          ),
          if (_byPercent)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Isi angka minus untuk harga turun, mis. -10.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 20),
          if (_result != null)
            FutureBuilder<List<SimulationRow>>(
              future: _result,
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return const Text(
                    'Belum ada menu yang memakai bahan ini.',
                    style: TextStyle(color: AppColors.textMuted),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle('Menu terdampak (${rows.length})'),
                    const SizedBox(height: 8),
                    for (final r in rows) _ResultCard(row: r),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.row});

  final SimulationRow row;

  @override
  Widget build(BuildContext context) {
    String rp(Decimal v) => formatRupiah(toRupiah(v));
    final delta = toRupiah(row.delta);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.product.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'HPP ${rp(row.oldHpp)} → ${rp(row.newHpp)} '
                '(${delta > 0 ? '+' : ''}${formatRupiah(delta)})',
                style: TextStyle(
                  color: delta > 0
                      ? AppColors.danger
                      : delta < 0
                      ? AppColors.success
                      : AppColors.text,
                ),
              ),
              if (row.complete) ...[
                Text(
                  'Laba/pcs di harga ${formatRupiah(row.product.sellingPrice)}: '
                  '${rp(row.oldProfit)} → ${rp(row.newProfit)}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                if (row.suggestedPrice != null)
                  Text(
                    'Saran harga ${formatRupiah(row.suggestedPrice!)} '
                    'supaya margin tetap',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ] else
                const Text(
                  'HPP belum lengkap; laba dan saran harga tidak dihitung.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
