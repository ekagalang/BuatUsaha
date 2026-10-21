import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/purchase_preview.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/costing/money.dart';
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../cash/cash_account_picker.dart';
import '../common/widgets.dart';
import '../theme.dart';

class _Line {
  _Line();

  String? ingredientId;

  /// Harga per satuan dasar di belanja lama (mode ubah).
  Decimal? originalUnitCost;

  /// Item daftar belanja asal baris ini (FR-12.7).
  String? shoppingItemId;

  /// Harga masih perkiraan dari daftar belanja.
  bool estimated = false;
  List<UnitOption> units = const [];
  UnitOption? unit;
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Belanja bahan multi-item (FR-1.3, mockup `FormBelanja`); dengan
/// [purchaseId] menjadi layar ubah belanja = batalkan + catat ulang (FR-9.2,
/// mockup `UbahBelanja`). Dengan [fromShoppingList], baris terisi dari item
/// daftar belanja yang dicentang (FR-12.7, mockup `BelanjaDariDaftar`).
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key, this.purchaseId, this.fromShoppingList});

  /// `null` = belanja baru.
  final String? purchaseId;

  /// Id daftar belanja asal.
  final String? fromShoppingList;

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _note = TextEditingController();
  final _lines = [_Line()];
  var _date = DateUtils.dateOnly(DateTime.now());
  var _saving = false;
  late bool _loading =
      widget.purchaseId != null || widget.fromShoppingList != null;
  var _fromListCount = 0;
  String? _cashAccountId;

  /// Jam belanja lama dipertahankan saat diubah.
  DateTime? _originalAt;
  Timer? _debounce;
  Future<PurchaseEditPreview>? _preview;

  bool get _editing => widget.purchaseId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _load(widget.purchaseId!);
    if (widget.fromShoppingList != null) {
      _loadFromList(widget.fromShoppingList!);
    }
  }

  Future<void> _loadFromList(String listId) async {
    final stock = ref.read(stockRepositoryProvider);
    final items = await ref
        .read(shoppingRepositoryProvider)
        .linesToRecord(listId);
    final lines = <_Line>[];
    for (final l in items) {
      final id = l.item.ingredientId!;
      final units = await stock.unitOptions(id);
      final line = _Line()
        ..ingredientId = id
        ..units = units
        ..unit = units.firstWhere(
          (u) => u.name == l.item.unitName,
          orElse: () => UnitOption(
            name: l.item.unitName,
            factorToBase: dec(l.item.factorToBase),
          ),
        )
        ..shoppingItemId = l.item.id
        ..estimated = true;
      line.qty.text = formatDecimal(dec(l.item.qty), maxDecimals: 3);
      final cost = l.item.estimatedCost;
      if (cost != null) line.price.text = formatRupiahDigits(cost);
      lines.add(line);
    }
    if (!mounted) return;
    setState(() {
      if (lines.isNotEmpty) {
        for (final old in _lines) {
          old.dispose();
        }
        _lines
          ..clear()
          ..addAll(lines);
      }
      _fromListCount = lines.length;
      _loading = false;
    });
  }

  Future<void> _load(String id) async {
    final repo = ref.read(stockRepositoryProvider);
    final input = await repo.loadPurchase(id);
    final lines = <_Line>[];
    for (final l in input.lines) {
      final units = await repo.unitOptions(l.ingredientId);
      final line = _Line()
        ..ingredientId = l.ingredientId
        ..units = units
        ..unit = units.firstWhere(
          (u) => u.name == l.unitName,
          orElse: () =>
              UnitOption(name: l.unitName, factorToBase: l.factorToBase),
        )
        ..originalUnitCost = divide(rupiah(l.totalPrice), l.qtyBase);
      line.qty.text = formatDecimal(l.qty, maxDecimals: 3);
      line.price.text = formatRupiahDigits(l.totalPrice);
      lines.add(line);
    }
    if (!mounted) return;
    setState(() {
      for (final old in _lines) {
        old.dispose();
      }
      _lines
        ..clear()
        ..addAll(lines);
      _originalAt = input.purchasedAt.toLocal();
      _date = DateUtils.dateOnly(_originalAt!);
      _note.text = input.note ?? '';
      _cashAccountId = input.cashAccountId;
      _loading = false;
    });
    _schedulePreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    if (_editing) _schedulePreview();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final input = _input();
      if (input == null || !mounted) return;
      final business = await ref.read(currentBusinessProvider.future);
      if (!mounted) return;
      setState(() {
        _preview = ref
            .read(purchasePreviewerProvider)
            .preview(business.id, widget.purchaseId!, input);
      });
    });
  }

  /// `null` jika ada item yang belum lengkap.
  PurchaseInput? _input() {
    final lines = <PurchaseLineInput>[];
    for (final line in _lines) {
      final qty = parseDecimalInput(line.qty.text);
      final price = parseRupiahInput(line.price.text);
      final unit = line.unit;
      if (line.ingredientId == null ||
          unit == null ||
          qty == null ||
          qty <= Decimal.zero ||
          price == null) {
        return null;
      }
      lines.add(
        PurchaseLineInput(
          ingredientId: line.ingredientId!,
          qty: qty,
          unitName: unit.name,
          factorToBase: unit.factorToBase,
          totalPrice: price,
        ),
      );
    }
    final time = _originalAt ?? DateTime.now();
    return PurchaseInput(
      purchasedAt: DateTime(
        _date.year,
        _date.month,
        _date.day,
        time.hour,
        time.minute,
      ),
      lines: lines,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      cashAccountId: _cashAccountId,
    );
  }

  int get _total => _lines.fold(
    0,
    (sum, line) => sum + (parseRupiahInput(line.price.text) ?? 0),
  );

  Future<void> _pickIngredient(_Line line, String id) async {
    final units = await ref.read(stockRepositoryProvider).unitOptions(id);
    final custom = units.where((u) => u.isCustom);
    final preferred = custom.isNotEmpty
        ? custom.first
        : units.firstWhere(
            (u) => u.name == 'kg' || u.name == 'liter',
            orElse: () => units.first,
          );
    setState(() {
      line
        ..ingredientId = id
        ..units = units
        ..unit = preferred;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final input = _input();
    if (input == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Lengkapi bahan, jumlah, dan total harga tiap item.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(stockRepositoryProvider);
      if (_editing) {
        await repo.replacePurchase(widget.purchaseId!, input, reason: 'Diubah');
      } else {
        final business = await ref.read(currentBusinessProvider.future);
        final id = await repo.recordPurchase(business.id, input);
        final fromList = [
          for (final line in _lines)
            if (line.shoppingItemId != null) line.shoppingItemId!,
        ];
        if (fromList.isNotEmpty) {
          // Item daftar belanja ditandai Tercatat (FR-12.7).
          await ref.read(shoppingRepositoryProvider).markRecorded(fromList, id);
        }
      }
      if (!mounted) return;
      await Navigator.of(context).maybePop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? 'Belanja diubah; harga rata-rata dan HPP dihitung ulang.'
                : 'Belanja ${formatRupiah(_total)} disimpan.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $error')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _editing ? 'Ubah belanja' : 'Belanja bahan';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    final byId = {for (final v in ingredients) v.ingredient.id: v};
    final closed = _editing
        ? closedDayWarning(ref.watch(businessProvider).value, _date)
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ingredients.isEmpty
          ? _NoIngredients(onAdd: () => context.push('/bahan/baru'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                if (_fromListCount > 0) ...[
                  InfoBox(
                    'Dari daftar belanja: $_fromListCount bahan yang dicentang. '
                    'Jumlah dan harga masih perkiraan; sesuaikan dengan struk.',
                    kind: StatusKind.neutral,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_editing) ...[
                  const InfoBox(
                    'Belanja lama tetap terlihat di kartu stok sebagai '
                    'Dibatalkan, lalu diganti versi ini. Harga rata-rata '
                    'dihitung ulang sejak tanggal belanja.',
                    kind: StatusKind.neutral,
                  ),
                  if (closed != null) ...[
                    const SizedBox(height: 8),
                    InfoBox(closed),
                  ],
                  const SizedBox(height: 16),
                ],
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal belanja',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(formatLongDate(_date)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Toko atau catatan (opsional)',
                  ),
                ),
                const SizedBox(height: 12),
                CashAccountPicker(
                  value: _cashAccountId,
                  onChanged: (id) {
                    _cashAccountId = id;
                    _changed();
                  },
                ),
                const SizedBox(height: 20),
                const SectionTitle('Item belanja'),
                const SizedBox(height: 12),
                for (final (i, line) in _lines.indexed) ...[
                  _LineCard(
                    line: line,
                    ingredients: ingredients,
                    view: byId[line.ingredientId],
                    editing: _editing,
                    onIngredient: (id) => _pickIngredient(line, id),
                    onChanged: _changed,
                    onRemove: _lines.length == 1
                        ? null
                        : () {
                            _lines.removeAt(i).dispose();
                            _changed();
                          },
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.dashed, width: 1.5),
                  ),
                  onPressed: () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah item'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/bahan/baru'),
                  child: const Text('Bahan belum ada di daftar? Tambah bahan'),
                ),
                if (_editing && _preview != null) ...[
                  const SizedBox(height: 8),
                  _EditImpact(preview: _preview!),
                ],
              ],
            ),
      bottomNavigationBar: ingredients.isEmpty
          ? null
          : BottomActionBar(
              above: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total belanja',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  Text(
                    formatRupiah(_total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Menyimpan…'
                      : _editing
                      ? 'Simpan perubahan'
                      : 'Simpan belanja',
                ),
              ),
            ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.ingredients,
    required this.view,
    required this.editing,
    required this.onIngredient,
    required this.onChanged,
    required this.onRemove,
  });

  final _Line line;
  final List<IngredientView> ingredients;
  final IngredientView? view;
  final bool editing;
  final ValueChanged<String> onIngredient;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: line.ingredientId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bahan'),
                    items: [
                      for (final v in ingredients)
                        DropdownMenuItem(
                          value: v.ingredient.id,
                          child: Text(v.ingredient.name),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) onIngredient(id);
                    },
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Hapus item',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: line.qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(labelText: 'Jumlah'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${line.ingredientId}-${line.units.length}'),
                    initialValue: line.unit?.name,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Satuan'),
                    items: [
                      for (final u in line.units)
                        DropdownMenuItem(
                          value: u.name,
                          child: Text(
                            u.isCustom
                                ? '${u.name} (${formatDecimal(u.factorToBase)} '
                                      '${view?.ingredient.baseUnit.code ?? ''})'
                                : u.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (name) {
                      line.unit = line.units.firstWhere((u) => u.name == name);
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: line.price,
              keyboardType: TextInputType.number,
              onChanged: (_) => onChanged(),
              inputFormatters: const [RupiahInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Total harga',
                prefixText: 'Rp ',
                helperText: line.estimated
                    ? 'Harga perkiraan dari harga rata-rata; ganti sesuai struk.'
                    : null,
                helperMaxLines: 2,
              ),
            ),
            if (view != null && line.unit != null && !editing) ...[
              const SizedBox(height: 10),
              _Preview(line: line, view: view!),
            ],
            if (view != null && line.unit != null && editing)
              _unitPriceNote(view!),
          ],
        ),
      ),
    );
  }
}

extension on _LineCard {
  /// "Rp14/g · sebelumnya Rp140/g" di layar ubah belanja.
  Widget _unitPriceNote(IngredientView view) {
    final base = view.ingredient.baseUnit.code;
    final qty = parseDecimalInput(line.qty.text);
    final price = parseRupiahInput(line.price.text);
    final now = qty == null || qty <= Decimal.zero || price == null
        ? null
        : divide(rupiah(price), qty * line.unit!.factorToBase);
    final before = line.originalUnitCost;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        [
          if (now != null) formatUnitPrice(now, base),
          if (before != null) 'sebelumnya ${formatUnitPrice(before, base)}',
        ].join(' · '),
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
    );
  }
}

/// Dampak ubah belanja sebelum disimpan (mockup `UbahBelanja`).
class _EditImpact extends StatelessWidget {
  const _EditImpact({required this.preview});

  final Future<PurchaseEditPreview> preview;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PurchaseEditPreview>(
      future: preview,
      builder: (context, snap) {
        final p = snap.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('Setelah disimpan'),
                const SizedBox(height: 8),
                if (p == null)
                  Text(
                    snap.hasError
                        ? 'Dampak belum bisa dihitung: ${snap.error}'
                        : 'Menghitung dampak…',
                    style: const TextStyle(color: AppColors.textMuted),
                  )
                else ...[
                  for (final a in p.ingredients)
                    _impactRow(
                      'Harga rata-rata ${a.name.toLowerCase()}',
                      '${formatUnitPrice(a.before, a.unit)} → '
                          '${formatUnitPrice(a.after, a.unit)}',
                    ),
                  for (final m in p.menus)
                    _impactRow(
                      'HPP ${m.name.toLowerCase()} per pcs',
                      '${formatRupiah(toRupiah(m.before))} → '
                          '${formatRupiah(toRupiah(m.after))}',
                    ),
                  if (p.ordersAffected > 0) ...[
                    const SizedBox(height: 8),
                    InfoBox(
                      '${p.ordersAffected} pesanan selesai masih memakai HPP '
                      'lama. Tinjau dan hitung ulang lewat Beranda › Perlu '
                      'perhatian.',
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _impactRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview({required this.line, required this.view});

  final _Line line;
  final IngredientView view;

  @override
  Widget build(BuildContext context) {
    final base = view.ingredient.baseUnit.code;
    final qty = parseDecimalInput(line.qty.text);
    final price = parseRupiahInput(line.price.text);
    if (qty == null || qty <= Decimal.zero || price == null) {
      return const SizedBox.shrink();
    }
    final qtyBase = qty * line.unit!.factorToBase;
    final unitCost = divide(rupiah(price), qtyBase);
    final oldAvg = view.avgUnitCost;
    final replaces =
        oldAvg == null ||
        view.ingredient.priceIsEstimate ||
        view.stock <= Decimal.zero;
    final newAvg = replaces
        ? unitCost
        : divide(view.stock * oldAvg + rupiah(price), view.stock + qtyBase);
    final before = oldAvg == null
        ? 'Belum ada harga'
        : formatUnitPrice(oldAvg, base) +
              (view.ingredient.priceIsEstimate ? ' (perkiraan)' : '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cell,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _row('Harga per $base', formatUnitPrice(unitCost, base)),
          _row(
            'Harga rata-rata',
            '$before → ${formatUnitPrice(newAvg, base)}',
            strong: true,
          ),
          _row(
            'Stok',
            '${formatDecimal(view.stock, maxDecimals: 3)} → '
                '${formatQty(view.stock + qtyBase, base)}',
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _NoIngredients extends StatelessWidget {
  const _NoIngredients({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Belum ada bahan. Tambahkan bahan dulu, lalu catat belanjanya.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Tambah bahan'),
            ),
          ],
        ),
      ),
    );
  }
}
