import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/costing/money.dart';
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

class _Line {
  String? ingredientId;
  List<UnitOption> units = const [];
  UnitOption? unit;
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Belanja bahan multi-item (FR-1.3, mockup `FormBelanja`).
class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _note = TextEditingController();
  final _lines = [_Line()];
  var _date = DateUtils.dateOnly(DateTime.now());
  var _saving = false;

  @override
  void dispose() {
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
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
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Lengkapi bahan, jumlah, dan total harga tiap item.'),
          ),
        );
        return;
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
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final business = await ref.read(currentBusinessProvider.future);
      await ref
          .read(stockRepositoryProvider)
          .recordPurchase(
            business.id,
            PurchaseInput(
              purchasedAt: DateTime(
                _date.year,
                _date.month,
                _date.day,
                now.hour,
                now.minute,
              ),
              lines: lines,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            ),
          );
      if (!mounted) return;
      context.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Belanja ${formatRupiah(_total)} disimpan.')),
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
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    final byId = {for (final v in ingredients) v.ingredient.id: v};
    return Scaffold(
      appBar: AppBar(title: const Text('Belanja bahan')),
      body: ingredients.isEmpty
          ? _NoIngredients(onAdd: () => context.push('/bahan/baru'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
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
                const SizedBox(height: 20),
                const SectionTitle('Item belanja'),
                const SizedBox(height: 12),
                for (final (i, line) in _lines.indexed) ...[
                  _LineCard(
                    line: line,
                    ingredients: ingredients,
                    view: byId[line.ingredientId],
                    onIngredient: (id) => _pickIngredient(line, id),
                    onChanged: () => setState(() {}),
                    onRemove: _lines.length == 1
                        ? null
                        : () => setState(() {
                            _lines.removeAt(i).dispose();
                          }),
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
                child: Text(_saving ? 'Menyimpan…' : 'Simpan belanja'),
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
    required this.onIngredient,
    required this.onChanged,
    required this.onRemove,
  });

  final _Line line;
  final List<IngredientView> ingredients;
  final IngredientView? view;
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
              decoration: const InputDecoration(
                labelText: 'Total harga',
                prefixText: 'Rp ',
              ),
            ),
            if (view != null && line.unit != null) ...[
              const SizedBox(height: 10),
              _Preview(line: line, view: view!),
            ],
          ],
        ),
      ),
    );
  }
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
