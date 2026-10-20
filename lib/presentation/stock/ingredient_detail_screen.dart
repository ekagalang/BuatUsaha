import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'labels.dart';

/// Detail bahan: ringkasan, aksi stok, dan kartu stok (FR-1.4, FR-1.5, FR-9.1).
class IngredientDetailScreen extends ConsumerWidget {
  const IngredientDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(ingredientProvider(id));
    final card = ref.watch(stockCardProvider(id));
    return view.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Gagal memuat bahan: $error')),
      ),
      data: (v) => Scaffold(
        appBar: AppBar(
          title: Text(v.ingredient.name),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Pengaturan bahan',
              onSelected: (action) => switch (action) {
                'unit' => _addUnit(context, ref, v),
                _ => _editMinStock(context, ref, v),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'unit', child: Text('Tambah satuan beli')),
                PopupMenuItem(value: 'min', child: Text('Ubah stok minimum')),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _Summary(view: v),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _adjust(context, ref, v),
                  icon: const Icon(Icons.tune),
                  label: const Text('Penyesuaian'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _waste(context, ref, v),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Bahan rusak'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _opname(context, ref, v),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Stock opname'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _UsedInMenus(ingredient: v),
            const SizedBox(height: 24),
            const SectionTitle('Kartu stok'),
            const SizedBox(height: 4),
            const Text(
              'Belanja bisa diubah atau dibatalkan; baris lain dibatalkan '
              'dengan mengetuknya. Baris yang dibatalkan tetap terlihat dan '
              'saldo dihitung ulang.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            card.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text('Gagal memuat kartu stok: $error'),
              data: (entries) => entries.isEmpty
                  ? const Text(
                      'Belum ada mutasi.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, entry) in entries.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _cardRow(context, ref, v, entry),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardRow(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
    StockCardEntry entry,
  ) {
    final m = entry.movement;
    final active = !entry.cancelled && !entry.isReversal;
    final isPurchase = m.refType == 'purchase_item' && active;
    return _CardRow(
      entry: entry,
      unit: v.ingredient.baseUnit.code,
      onTap: active && !isPurchase ? () => _void(context, ref, entry) : null,
      onEdit: isPurchase
          ? () async {
              final purchaseId = await ref
                  .read(stockRepositoryProvider)
                  .purchaseIdOfItem(m.refId!);
              if (context.mounted) {
                await context.push('/bahan/belanja/$purchaseId');
              }
            }
          : null,
      onVoid: isPurchase ? () => _void(context, ref, entry) : null,
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $error')));
    }
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
  ) async {
    final result = await showDialog<(Decimal, String?)>(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Penyesuaian stok',
        qtyLabel: 'Jumlah',
        unit: v.ingredient.baseUnit.code,
        withDirection: true,
        noteLabel: 'Alasan (opsional)',
      ),
    );
    if (result == null || !context.mounted) return;
    final (qty, note) = result;
    await _run(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .recordAdjustment(v.ingredient.id, qtyBase: qty, note: note),
      'Penyesuaian dicatat.',
    );
  }

  Future<void> _waste(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
  ) async {
    final result = await showDialog<(Decimal, String?)>(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Bahan rusak atau kedaluwarsa',
        qtyLabel: 'Jumlah dibuang',
        unit: v.ingredient.baseUnit.code,
        noteLabel: 'Keterangan (opsional)',
        helper: 'Dicatat sebagai kerugian dengan harga rata-rata saat ini.',
      ),
    );
    if (result == null || !context.mounted) return;
    final (qty, note) = result;
    await _run(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .recordWaste(v.ingredient.id, qtyBase: qty, note: note),
      'Bahan rusak dicatat.',
    );
  }

  Future<void> _opname(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
  ) async {
    final unit = v.ingredient.baseUnit.code;
    final result = await showDialog<(Decimal, String?)>(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Stock opname',
        qtyLabel: 'Stok fisik sekarang',
        unit: unit,
        noteLabel: 'Catatan (opsional)',
        helper:
            'Stok di aplikasi: ${formatQty(v.stock, unit)}. Selisihnya '
            'dicatat otomatis.',
        allowZero: true,
      ),
    );
    if (result == null || !context.mounted) return;
    final (counted, note) = result;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final delta = await ref
          .read(stockRepositoryProvider)
          .recordOpname(v.ingredient.id, countedQty: counted, note: note);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            delta == Decimal.zero
                ? 'Stok sudah cocok.'
                : 'Selisih ${formatQty(delta, unit)} dicatat.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $error')));
    }
  }

  Future<void> _void(
    BuildContext context,
    WidgetRef ref,
    StockCardEntry entry,
  ) async {
    final movement = entry.movement;
    final isPurchase = movement.refType == 'purchase_item';
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: isPurchase ? 'Batalkan belanja ini?' : 'Batalkan mutasi ini?',
        message: isPurchase
            ? 'Seluruh item dalam belanja ini ikut dibatalkan. Harga '
                  'rata-rata dan saldo dihitung ulang.'
            : 'Saldo dan harga rata-rata dihitung ulang tanpa mutasi ini.',
        warning: closedDayWarning(
          ref.read(businessProvider).value,
          movement.occurredAt,
        ),
      ),
    );
    if (reason == null || !context.mounted) return;
    final repo = ref.read(stockRepositoryProvider);
    await _run(context, () async {
      if (isPurchase) {
        final purchaseId = await repo.purchaseIdOfItem(movement.refId!);
        await repo.voidPurchase(purchaseId, reason: reason);
      } else {
        await repo.voidMovement(movement.id, reason: reason);
      }
    }, 'Dibatalkan.');
  }

  Future<void> _addUnit(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
  ) async {
    final result = await showDialog<(String, Decimal)>(
      context: context,
      builder: (_) => _UnitDialog(baseUnit: v.ingredient.baseUnit.code),
    );
    if (result == null || !context.mounted) return;
    final (name, factor) = result;
    await _run(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .addCustomUnit(v.ingredient.id, unitName: name, factorToBase: factor),
      'Satuan $name ditambahkan.',
    );
  }

  Future<void> _editMinStock(
    BuildContext context,
    WidgetRef ref,
    IngredientView v,
  ) async {
    final result = await showDialog<(Decimal, String?)>(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Stok minimum',
        qtyLabel: 'Batas minimum',
        unit: v.ingredient.baseUnit.code,
        initial: v.minStock,
        allowZero: true,
        helper: 'Isi 0 jika bahan ini tidak perlu dipantau.',
      ),
    );
    if (result == null || !context.mounted) return;
    final (minStock, _) = result;
    await _run(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .updateIngredient(v.ingredient.id, minStock: minStock),
      'Stok minimum diperbarui.',
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.view});

  final IngredientView view;

  @override
  Widget build(BuildContext context) {
    final unit = view.ingredient.baseUnit.code;
    final avg = view.avgUnitCost;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                StatusPill(
                  categoryLabel(view.ingredient.category),
                  kind: StatusKind.neutral,
                ),
                if (view.isLow)
                  const StatusPill('Menipis', kind: StatusKind.danger),
                if (avg == null)
                  const StatusPill('Belum ada harga', kind: StatusKind.warning)
                else if (view.ingredient.priceIsEstimate)
                  const StatusPill('Harga perkiraan', kind: StatusKind.neutral),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat('Stok', formatQty(view.stock, unit)),
                _Stat('Harga rata-rata', formatUnitPrice(avg, unit)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat(
                  'Nilai sisa',
                  avg == null ? '—' : formatRupiah(view.value),
                ),
                _Stat(
                  'Minimum',
                  view.minStock > Decimal.zero
                      ? formatQty(view.minStock, unit)
                      : 'Tidak dipantau',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.entry,
    required this.unit,
    this.onTap,
    this.onEdit,
    this.onVoid,
  });

  final StockCardEntry entry;
  final String unit;
  final VoidCallback? onTap;

  /// Baris belanja: tombol Ubah belanja dan Batalkan (mockup `DetailBahan`).
  final VoidCallback? onEdit;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final m = entry.movement;
    final qty = dec(m.qtyBase);
    final isEstimate = qty == Decimal.zero && m.reversalOfId == null;
    var title = movementLabel(m.type, zeroQty: qty == Decimal.zero);
    if (entry.isReversal) title = 'Pembatalan $title';
    final details = [
      '${formatShortDate(m.occurredAt)}, ${formatTime(m.occurredAt)}',
      if (m.type == MovementType.purchase && !entry.isReversal)
        formatUnitPrice(dec(m.unitCost), unit),
      ?m.note,
    ].join(' · ');
    final muted = entry.cancelled || entry.isReversal;
    final amount = isEstimate
        ? formatUnitPrice(dec(m.unitCost), unit)
        : '${qty > Decimal.zero ? '+' : ''}${formatQty(qty, unit)}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: muted ? AppColors.textMuted : AppColors.text,
                            decoration: entry.cancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (entry.cancelled) ...[
                        const SizedBox(width: 8),
                        const Flexible(
                          child: StatusPill(
                            'Dibatalkan',
                            kind: StatusKind.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                          ),
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Ubah belanja'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: onVoid,
                          child: const Text('Batalkan'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: muted ? AppColors.textMuted : AppColors.text,
                    decoration: entry.cancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (!muted && !isEstimate)
                  Text(
                    'saldo ${formatQty(dec(m.balanceAfter), unit)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog jumlah + catatan; [withDirection] menambah pilihan tambah/kurangi.
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({
    required this.title,
    required this.qtyLabel,
    required this.unit,
    this.noteLabel,
    this.helper,
    this.withDirection = false,
    this.allowZero = false,
    this.initial,
  });

  final String title;
  final String qtyLabel;
  final String unit;
  final String? noteLabel;
  final String? helper;
  final bool withDirection;
  final bool allowZero;
  final Decimal? initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _qty = TextEditingController(
    text: widget.initial == null
        ? ''
        : formatDecimal(widget.initial!, maxDecimals: 3),
  );
  final _note = TextEditingController();
  var _increase = false;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Decimal? get _value {
    final qty = parseDecimalInput(_qty.text);
    if (qty == null || qty < Decimal.zero) return null;
    if (qty == Decimal.zero && !widget.allowZero) return null;
    if (!widget.withDirection) return qty;
    return _increase ? qty : -qty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.withDirection) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Kurangi')),
                  ButtonSegment(value: true, label: Text('Tambah')),
                ],
                selected: {_increase},
                onSelectionChanged: (s) => setState(() => _increase = s.first),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.qtyLabel,
                suffixText: widget.unit,
                helperText: widget.helper,
                helperMaxLines: 3,
              ),
            ),
            if (widget.noteLabel != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: InputDecoration(labelText: widget.noteLabel),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _value == null
              ? null
              : () {
                  final note = _note.text.trim();
                  Navigator.pop(context, (_value!, note.isEmpty ? null : note));
                },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _UnitDialog extends StatefulWidget {
  const _UnitDialog({required this.baseUnit});

  final String baseUnit;

  @override
  State<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<_UnitDialog> {
  final _name = TextEditingController();
  final _factor = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _factor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final factor = parseDecimalInput(_factor.text);
    final valid = name.isNotEmpty && factor != null && factor > Decimal.zero;
    return AlertDialog(
      title: const Text('Tambah satuan beli'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Nama satuan',
              hintText: 'mis. rak, pack, karung',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _factor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '1 ${name.isEmpty ? 'satuan' : name} berisi',
              suffixText: widget.baseUnit,
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
          onPressed: valid
              ? () => Navigator.pop(context, (name, factor))
              : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Menu yang resepnya memakai bahan ini (PRD 7, mockup `DetailBahan`).
class _UsedInMenus extends ConsumerWidget {
  const _UsedInMenus({required this.ingredient});

  final IngredientView ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ingredient.ingredient.id;
    final unit = ingredient.ingredient.baseUnit.code;
    final avg = ingredient.avgUnitCost;
    final menus = [
      for (final p
          in ref.watch(productsProvider).value ?? const <ProductView>[])
        for (final l in p.costing.lines)
          if (l.ingredient.id == id) (p, dec(l.item.qtyBase)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Dipakai di menu',
          trailing: Text(
            '${menus.length} menu',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        if (menus.isEmpty)
          const Text(
            'Belum dipakai di resep mana pun.',
            style: TextStyle(color: AppColors.textMuted),
          )
        else ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, (p, qty)) in menus.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => context.push('/menu/${p.product.id}'),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      p.product.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (p.status == HppStatus.incomplete)
                                      const StatusPill(
                                        'HPP belum lengkap',
                                        kind: StatusKind.warning,
                                      ),
                                  ],
                                ),
                                Text(
                                  [
                                    '${formatQty(qty, unit)} per resep',
                                    if (p.capacity != null)
                                      'bisa jadi ${p.capacity!.maxPcs} pcs',
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            avg == null
                                ? '—'
                                : formatRupiah(toRupiah(qty * avg)),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Biaya = takaran per resep × harga rata-rata sekarang. Jika harga '
            '${ingredient.ingredient.name.toLowerCase()} berubah, HPP '
            '${menus.length == 1 ? 'menu ini' : 'menu-menu ini'} ikut dihitung '
            'ulang.',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}
