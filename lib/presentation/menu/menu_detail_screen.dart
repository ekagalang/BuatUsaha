import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'menu_labels.dart';

/// Detail menu: HPP, saran harga, rincian, kapasitas, simulasi target, stok
/// produk jadi, dan riwayat produksi (mockup `DetailMenu`).
class MenuDetailScreen extends ConsumerWidget {
  const MenuDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productProvider(id));
    return product.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Gagal memuat menu: $error')),
      ),
      data: (view) => _Detail(view: view),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.view});

  final ProductView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = view.product;
    final subtitle = [
      modeLabel(view.mode),
      '1 resep = ${formatDecimal(dec(product.yieldQty))} pcs',
      if (product.shelfLifeDays != null)
        'umur simpan ${product.shelfLifeDays} hari',
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => context.push('/menu/${product.id}/ubah'),
              child: const Text('Ubah resep'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          _HppHero(view: view),
          ..._notices(),
          if (view.suggestedByMarkup != null) ...[
            const SizedBox(height: 20),
            _PriceSuggestion(view: view),
          ],
          const SizedBox(height: 20),
          _Breakdown(view: view),
          if (view.capacity != null) ...[
            const SizedBox(height: 20),
            _Capacity(view: view),
            const SizedBox(height: 20),
            _TargetSimulation(view: view),
          ],
          if (view.isReadyStock) ...[
            const SizedBox(height: 20),
            _FinishedStock(view: view),
          ],
          const SizedBox(height: 20),
          _ProductionHistory(productId: product.id),
        ],
      ),
      bottomNavigationBar: view.costing.lines.isEmpty || !view.isReadyStock
          ? null
          : BottomActionBar(
              child: FilledButton.icon(
                onPressed: () => _recordProduction(context, ref),
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('Catat produksi'),
              ),
            ),
    );
  }

  List<Widget> _notices() {
    final notices = <(String, StatusKind)>[];
    final missing = view.hpp.missingPriceIngredientIds
        .map(view.ingredientName)
        .whereType<String>()
        .toList();
    if (view.costing.lines.isEmpty) {
      notices.add((
        'Resep belum punya bahan. Ketuk "Ubah resep" untuk mengisi takaran.',
        StatusKind.warning,
      ));
    }
    if (missing.isNotEmpty) {
      notices.add((
        'HPP belum lengkap: ${missing.join(', ')} belum ada harga. Catat '
            'belanja atau isi harga perkiraan di tab Bahan.',
        StatusKind.warning,
      ));
    }
    if (view.costing.wageMissing) {
      notices.add((
        'Upah per jam pemilik belum diisi. Isi lewat "Ubah resep".',
        StatusKind.warning,
      ));
    }
    if (!view.isReadyStock && view.costing.lines.isNotEmpty) {
      notices.add((
        'Menu pre-order: bahan dipotong saat pesanan selesai. Produksi untuk '
            'pesanan dicatat dari detail pesanan.',
        StatusKind.neutral,
      ));
    }
    if (view.status == HppStatus.estimated) {
      notices.add((
        'Sebagian harga bahan masih perkiraan; HPP jadi pasti setelah belanja '
            'dicatat.',
        StatusKind.neutral,
      ));
    }
    switch (view.warning) {
      case PriceWarning.belowHpp:
        notices.add((
          'Harga jual di bawah HPP: setiap pcs terjual rugi '
              '${formatRupiah(toRupiah(-view.profitPerPcs!))}.',
          StatusKind.danger,
        ));
      case PriceWarning.belowTargetMargin:
        notices.add((
          'Margin di bawah target markup ${formatDecimal(view.markupTarget)}%.',
          StatusKind.warning,
        ));
      case null:
    }
    return [
      for (final (text, kind) in notices) ...[
        const SizedBox(height: 10),
        InfoBox(text, kind: kind),
      ],
    ];
  }

  Future<void> _recordProduction(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_ProductionInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductionSheet(view: view),
    );
    if (result == null || !context.mounted) return;
    final output = result.batchQty * dec(view.product.yieldQty);
    await runWithSnack(
      context,
      () => ref
          .read(productRepositoryProvider)
          .recordProduction(
            view.product.id,
            batchQty: result.batchQty,
            actualUsage: result.usage,
            note: result.note,
          ),
      view.isReadyStock
          ? 'Produksi dicatat: ${formatDecimal(output)} pcs masuk stok.'
          : 'Produksi dicatat.',
    );
  }
}

class _HppHero extends StatelessWidget {
  const _HppHero({required this.view});

  final ProductView view;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = hppStatusPill(view.status);
    final profit = view.profitPerPcs;
    const muted = TextStyle(fontSize: 12, color: AppColors.onPrimaryMuted);
    const strong = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary,
    );
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          Text(value, style: strong),
        ],
      ),
    );
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
              const Expanded(
                child: Text(
                  'HPP per pcs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimaryMuted,
                  ),
                ),
              ),
              StatusPill(label, kind: kind),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            formatHpp(view),
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontSize: 34, color: AppColors.onPrimary),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF8A5A40), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              stat('Harga jual', formatRupiah(view.product.sellingPrice)),
              stat(
                'Laba/pcs',
                profit == null ? '—' : formatRupiah(toRupiah(profit)),
              ),
              stat('Margin', formatMargin(view)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceSuggestion extends ConsumerStatefulWidget {
  const _PriceSuggestion({required this.view});

  final ProductView view;

  @override
  ConsumerState<_PriceSuggestion> createState() => _PriceSuggestionState();
}

class _PriceSuggestionState extends ConsumerState<_PriceSuggestion> {
  static final _margins = [Decimal.fromInt(30), Decimal.fromInt(40)];
  var _byMargin = false;
  late Decimal _margin = _margins.last;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final rounding = view.business.priceRounding;
    final markup = view.markupTarget;
    final price = _byMargin
        ? view.suggestedByMargin(_margin)!
        : view.suggestedByMarkup!;
    final raw = _byMargin
        ? divide(view.hppPerPcs * hundred, hundred - _margin)
        : divide(view.hppPerPcs * (hundred + markup), hundred);
    final same = price == view.product.sellingPrice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Saran harga jual'),
            const SizedBox(height: 10),
            Segmented(
              labels: [
                'Markup ${formatDecimal(markup)}%',
                for (final m in _margins) 'Margin ${formatDecimal(m)}%',
              ],
              selected: _byMargin ? 1 + _margins.indexOf(_margin) : 0,
              onSelected: (i) => setState(() {
                _byMargin = i > 0;
                if (i > 0) _margin = _margins[i - 1];
              }),
            ),
            const SizedBox(height: 12),
            Text(
              formatRupiah(price),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            Text(
              'dari ${formatRupiah(toRupiah(raw))}, dibulatkan ke atas ke '
              '${formatRupiah(rounding)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: same
                    ? null
                    : () => runWithSnack(
                        context,
                        () => ref
                            .read(productRepositoryProvider)
                            .setSellingPrice(view.product.id, price),
                        'Harga jual diubah ke ${formatRupiah(price)}.',
                      ),
                child: Text(same ? 'Sudah dipakai' : 'Pakai harga ini'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.view});

  final ProductView view;

  @override
  Widget build(BuildContext context) {
    final hpp = view.hpp;
    final costing = view.costing;
    final yieldLabel = formatDecimal(dec(view.product.yieldQty));
    final perBatch = costing.costs.where((c) => c.basis == CostBasis.perBatch);
    final perPcs = costing.costs.where((c) => c.basis == CostBasis.perPcs);
    String detailOf(ProductCost cost) {
      final hours = cost.laborHours;
      final wage = costing.ownerHourlyWage;
      if (hours == null) return '';
      return wage == null
          ? '${formatDecimal(dec(hours))} jam × upah belum diisi'
          : '${formatDecimal(dec(hours))} jam × ${formatRupiah(wage)}/jam';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Rincian HPP per resep'),
            const SizedBox(height: 8),
            for (final l in costing.lines)
              _Line(
                l.ingredient.name,
                detail:
                    '${formatQty(dec(l.item.qtyBase), l.ingredient.baseUnit.code)}'
                    ' × ${formatUnitPrice(l.line.unitCost, l.ingredient.baseUnit.code)}',
                value: l.line.cost == null
                    ? '—'
                    : formatRupiah(toRupiah(l.line.cost!)),
                warn: l.line.cost == null,
              ),
            _Line(
              'Total bahan',
              value: formatRupiah(toRupiah(hpp.materialCostPerBatch)),
              bold: true,
              divider: true,
            ),
            for (final c in perBatch)
              _Line(
                c.name,
                detail: detailOf(c),
                value: formatRupiah(costing.amountOf(c)),
                warn: c.laborHours != null && costing.ownerHourlyWage == null,
              ),
            _Line(
              'Total per resep',
              value: formatRupiah(toRupiah(hpp.totalCostPerBatch)),
              bold: true,
              divider: true,
            ),
            _Line(
              '÷ $yieldLabel pcs',
              value: formatRupiah(
                toRupiah(divide(hpp.totalCostPerBatch, hpp.yieldQty)),
              ),
            ),
            for (final c in perPcs)
              _Line(
                '+ ${c.name} per pcs',
                value: formatRupiah(costing.amountOf(c)),
              ),
            _Line(
              'HPP per pcs',
              value: formatHpp(view),
              bold: true,
              divider: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
    this.label, {
    required this.value,
    this.detail = '',
    this.bold = false,
    this.divider = false,
    this.warn = false,
  });

  final String label;
  final String detail;
  final String value;
  final bool bold;
  final bool divider;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w700 : FontWeight.w500;
    return Column(
      children: [
        if (divider) const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    style: TextStyle(fontSize: 14, fontWeight: weight),
                    children: [
                      if (detail.isNotEmpty)
                        TextSpan(
                          text: '  $detail',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: warn
                                ? AppColors.warning
                                : AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: weight,
                  color: warn ? AppColors.warning : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Capacity extends StatelessWidget {
  const _Capacity({required this.view});

  final ProductView view;

  @override
  Widget build(BuildContext context) {
    final capacity = view.capacity!;
    final limiting = capacity.limitingIngredientIds.toSet();
    final names = limitingNames(view, capacity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              capacity.maxPcs > 0
                  ? 'Bisa jadi ${capacity.maxPcs} pcs'
                  : 'Belum bisa dibuat',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Dari stok sekarang. Pembatas: $names (cukup '
              '${formatDecimal(capacity.maxBatches, maxDecimals: 1)} resep).',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            for (final l in view.costing.lines)
              if (l.item.qtyBase > 0)
                _bar(l.ingredient, l.item.qtyBase, limiting),
          ],
        ),
      ),
    );
  }

  Widget _bar(Ingredient ingredient, double qtyPerBatch, Set<String> limiting) {
    final stock = dec(ingredient.currentStock);
    final ratio = divide(
      stock < Decimal.zero ? Decimal.zero : stock,
      dec(qtyPerBatch),
    );
    final isLimiting = limiting.contains(ingredient.id);
    final width = (ratio.toDouble() / 5).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isLimiting
                      ? '${ingredient.name} (pembatas)'
                      : ingredient.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isLimiting ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'cukup ${formatDecimal(ratio, maxDecimals: 1)} resep',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: width,
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              color: isLimiting ? AppColors.dangerStrong : AppColors.barNeutral,
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetSimulation extends StatefulWidget {
  const _TargetSimulation({required this.view});

  final ProductView view;

  @override
  State<_TargetSimulation> createState() => _TargetSimulationState();
}

class _TargetSimulationState extends State<_TargetSimulation> {
  late final List<int> _presets = () {
    final y = widget.view.product.yieldQty.ceil();
    return {y, y * 2, y * 5}.toList();
  }();
  late int _target = _presets.length > 1 ? _presets[1] : _presets.first;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final shortages = view.shortagesFor(_target);
    final byId = {for (final l in view.costing.lines) l.ingredient.id: l};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Mau buat berapa?'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pcs in _presets)
                  ChoicePill(
                    label: '$pcs pcs',
                    selected: _target == pcs,
                    onSelected: () => setState(() => _target = pcs),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (shortages.isEmpty)
              const InfoBox(
                'Stok cukup, tidak perlu belanja.',
                kind: StatusKind.success,
              )
            else ...[
              for (final s in shortages)
                _Line(
                  byId[s.ingredientId]?.ingredient.name ?? '',
                  detail:
                      'kurang ${formatQty(s.missingQty, byId[s.ingredientId]?.ingredient.baseUnit.code ?? '')}',
                  value: s.estimatedCost == null
                      ? 'belum ada harga'
                      : formatRupiah(toRupiah(s.estimatedCost!)),
                  warn: s.estimatedCost == null,
                ),
              _Line(
                'Perkiraan belanja',
                value: formatRupiah(estimateShoppingCost(shortages)),
                bold: true,
                divider: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinishedStock extends ConsumerWidget {
  const _FinishedStock({required this.view});

  final ProductView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = view.product;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Stok menu jadi',
              trailing: TextButton(
                onPressed: () => _opening(context, ref),
                child: const Text('Stok awal'),
              ),
            ),
            Text(
              '${formatDecimal(view.stock)} pcs',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(
              view.stock > Decimal.zero
                  ? 'Nilai ${formatRupiah(view.stockValue)} · HPP rata-rata '
                        '${formatRupiah(product.stockUnitCost.round())}/pcs'
                  : 'Stok bertambah saat produksi dicatat dan berkurang saat '
                        'terjual atau dibuang.',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _opening(BuildContext context, WidgetRef ref) async {
    final qty = await showDialog<Decimal>(
      context: context,
      builder: (_) => const _OpeningDialog(),
    );
    if (qty == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(productRepositoryProvider)
          .recordProductOpening(view.product.id, qty),
      'Stok awal ${formatDecimal(qty)} pcs dicatat.',
    );
  }
}

class _OpeningDialog extends StatefulWidget {
  const _OpeningDialog();

  @override
  State<_OpeningDialog> createState() => _OpeningDialogState();
}

class _OpeningDialogState extends State<_OpeningDialog> {
  final _qty = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = parseDecimalInput(_qty.text);
    final valid = qty != null && qty > Decimal.zero;
    return AlertDialog(
      title: const Text('Stok awal menu jadi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Untuk sisa jualan yang sudah ada sebelum memakai aplikasi. '
            'Dinilai dengan HPP sekarang, tanpa memotong bahan.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Jumlah',
              suffixText: 'pcs',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: valid ? () => Navigator.pop(context, qty) : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _ProductionHistory extends ConsumerWidget {
  const _ProductionHistory({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productions = ref.watch(productionsProvider(productId)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Riwayat produksi'),
        const SizedBox(height: 8),
        if (productions == null || productions.isEmpty)
          const Text(
            'Belum ada produksi.',
            style: TextStyle(color: AppColors.textMuted),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, p) in productions.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _row(context, ref, p),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Production p) {
    final voided = p.voidedAt != null;
    final style = TextStyle(
      decoration: voided ? TextDecoration.lineThrough : null,
      color: voided ? AppColors.textMuted : null,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatShortDate(p.producedAt)} ${formatTime(p.producedAt)}'
                  ' · ${formatDecimal(dec(p.batchQty))} resep → '
                  '${formatDecimal(dec(p.outputQty))} pcs',
                  style: style.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  voided
                      ? 'Dibatalkan: ${p.voidReason ?? ''}'
                      : 'HPP ${formatRupiah(p.hppPerPcs.round())}/pcs · bahan '
                            '${formatRupiah(p.materialCost)} · lain '
                            '${formatRupiah(p.otherCost)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!voided)
            IconButton(
              tooltip: 'Batalkan produksi',
              onPressed: () => _void(context, ref, p),
              icon: const Icon(Icons.undo, size: 20),
            ),
        ],
      ),
    );
  }

  Future<void> _void(BuildContext context, WidgetRef ref, Production p) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonDialog(
        title: 'Batalkan produksi ini?',
        message:
            'Bahan yang terpakai dikembalikan ke stok dan hasilnya dikeluarkan '
            'dari stok menu.',
      ),
    );
    if (reason == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(productRepositoryProvider)
          .voidProduction(p.id, reason: reason),
      'Produksi dibatalkan.',
    );
  }
}

class _ProductionInput {
  const _ProductionInput({
    required this.batchQty,
    required this.usage,
    this.note,
  });

  final Decimal batchQty;
  final Map<String, Decimal> usage;
  final String? note;
}

/// Catat produksi (FR-4.1, FR-4.2): jumlah resep, pemakaian bahan aktual
/// (bawaan = takaran × jumlah resep), dan catatan.
class _ProductionSheet extends StatefulWidget {
  const _ProductionSheet({required this.view});

  final ProductView view;

  @override
  State<_ProductionSheet> createState() => _ProductionSheetState();
}

class _ProductionSheetState extends State<_ProductionSheet> {
  final _batch = TextEditingController(text: '1');
  final _note = TextEditingController();
  late final Map<String, TextEditingController> _usage = {
    for (final l in widget.view.costing.lines)
      l.ingredient.id: TextEditingController(
        text: formatDecimal(dec(l.item.qtyBase), maxDecimals: 3),
      ),
  };

  /// Bahan yang takarannya diubah sendiri tidak ikut berubah saat jumlah
  /// resep diganti.
  final _edited = <String>{};
  var _showUsage = false;

  @override
  void dispose() {
    _batch.dispose();
    _note.dispose();
    for (final c in _usage.values) {
      c.dispose();
    }
    super.dispose();
  }

  Decimal? get _batchQty {
    final qty = parseDecimalInput(_batch.text);
    return qty == null || qty <= Decimal.zero ? null : qty;
  }

  void _onBatchChanged() {
    final batch = _batchQty;
    setState(() {
      if (batch == null) return;
      for (final l in widget.view.costing.lines) {
        if (_edited.contains(l.ingredient.id)) continue;
        _usage[l.ingredient.id]!.text = formatDecimal(
          dec(l.item.qtyBase) * batch,
          maxDecimals: 3,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final batch = _batchQty;
    final output = batch == null ? null : batch * dec(view.product.yieldQty);
    final short = <String>[];
    for (final l in view.costing.lines) {
      final qty = parseDecimalInput(_usage[l.ingredient.id]!.text);
      if (qty != null && qty > dec(l.ingredient.currentStock)) {
        short.add(l.ingredient.name);
      }
    }
    final blocked = short.isNotEmpty && !view.business.allowNegativeStock;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Catat produksi ${view.product.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batch,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _onBatchChanged(),
              decoration: InputDecoration(
                labelText: 'Jumlah resep',
                suffixText: 'resep',
                helperText: output == null
                    ? 'Boleh desimal, mis. 1,5'
                    : 'Hasil ${formatDecimal(output)} pcs'
                          '${view.isReadyStock ? ', masuk stok menu' : ''}',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => setState(() => _showUsage = !_showUsage),
              icon: Icon(_showUsage ? Icons.expand_less : Icons.expand_more),
              label: const Text('Pemakaian bahan aktual'),
            ),
            if (_showUsage)
              for (final l in view.costing.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _usage[l.ingredient.id],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {
                      _edited.add(l.ingredient.id);
                    }),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l.ingredient.name,
                      suffixText: l.ingredient.baseUnit.code,
                      helperText:
                          'stok ${formatQty(dec(l.ingredient.currentStock), l.ingredient.baseUnit.code)}',
                    ),
                  ),
                ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            if (short.isNotEmpty) ...[
              const SizedBox(height: 12),
              InfoBox(
                blocked
                    ? 'Stok ${short.join(', ')} tidak cukup. Catat belanja dulu.'
                    : 'Stok ${short.join(', ')} kurang; saldonya akan minus.',
                kind: blocked ? StatusKind.danger : StatusKind.warning,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: batch == null || blocked
                  ? null
                  : () => Navigator.pop(
                      context,
                      _ProductionInput(
                        batchQty: batch,
                        usage: {
                          for (final id in _edited)
                            id: ?parseDecimalInput(_usage[id]!.text),
                        },
                        note: _note.text.trim().isEmpty
                            ? null
                            : _note.text.trim(),
                      ),
                    ),
              child: const Text('Simpan produksi'),
            ),
          ],
        ),
      ),
    );
  }
}
