import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../domain/costing/money.dart';
import '../../domain/enums.dart';
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'labels.dart';

/// Form bahan baru dengan stok awal atau harga perkiraan (FR-1.1, FR-1.7).
class IngredientFormScreen extends ConsumerStatefulWidget {
  const IngredientFormScreen({super.key});

  @override
  ConsumerState<IngredientFormScreen> createState() =>
      _IngredientFormScreenState();
}

class _IngredientFormScreenState extends ConsumerState<IngredientFormScreen> {
  final _name = TextEditingController();
  final _minStock = TextEditingController();
  final _openingQty = TextEditingController();
  final _price = TextEditingController();
  var _category = IngredientCategory.raw;
  var _baseUnit = BaseUnit.g;
  late UnitOption _priceUnit = _defaultUnit(BaseUnit.g);
  var _saving = false;

  static UnitOption _defaultUnit(BaseUnit base) {
    final options = unitOptionsFor(base);
    return options.length > 1 && base != BaseUnit.pcs
        ? options.last
        : options.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _minStock.dispose();
    _openingQty.dispose();
    _price.dispose();
    super.dispose();
  }

  Decimal? get _qty => parseDecimalInput(_openingQty.text);

  /// Harga per satuan dasar dari "Rp X per satuan beli".
  Decimal? get _unitCost {
    final price = parseRupiahInput(_price.text);
    if (price == null || price <= 0) return null;
    return divide(rupiah(price), _priceUnit.factorToBase);
  }

  (String, StatusKind) get _hint {
    final unit = _baseUnit.code;
    final qty = _qty;
    final cost = _unitCost;
    final hasStock = qty != null && qty > Decimal.zero;
    if (cost == null) {
      return hasStock
          ? ('Stok awal perlu harga belinya.', StatusKind.danger)
          : (
              'Belum ada harga: HPP menu yang memakai bahan ini ditandai '
                  'belum lengkap sampai harga diisi atau belanja pertama dicatat.',
              StatusKind.warning,
            );
    }
    if (hasStock) {
      return (
        'Dicatat sebagai stok awal ${formatQty(qty, unit)} dengan harga '
            '${formatUnitPrice(cost, unit)}.',
        StatusKind.success,
      );
    }
    return (
      'Tanpa stok, ${formatUnitPrice(cost, unit)} dipakai sebagai harga '
          'perkiraan dan diganti otomatis oleh belanja pertama.',
      StatusKind.neutral,
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    final qty = _qty;
    final cost = _unitCost;
    final hasStock = qty != null && qty > Decimal.zero;
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nama bahan belum diisi.')),
      );
      return;
    }
    if (hasStock && cost == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Isi harga beli untuk stok awal.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      await ref
          .read(stockRepositoryProvider)
          .createIngredient(
            businessId: business.id,
            name: name,
            baseUnit: _baseUnit,
            category: _category,
            minStock: parseDecimalInput(_minStock.text),
            openingQty: hasStock ? qty : null,
            openingUnitCost: hasStock ? cost : null,
            estimatedUnitCost: hasStock ? null : cost,
          );
      if (!mounted) return;
      context.pop();
      messenger.showSnackBar(SnackBar(content: Text('$name disimpan.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $error')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = _baseUnit.code;
    final (hint, hintKind) = _hint;
    const number = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(title: const Text('Bahan baru')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nama bahan'),
          ),
          const SizedBox(height: 16),
          const _Label('Kategori'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in IngredientCategory.values)
                ChoicePill(
                  label: categoryLabel(category),
                  selected: _category == category,
                  onSelected: () => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Label('Satuan dasar'),
          Wrap(
            spacing: 8,
            children: [
              for (final base in BaseUnit.values)
                ChoicePill(
                  label: base.code,
                  selected: _baseUnit == base,
                  onSelected: () => setState(() {
                    _baseUnit = base;
                    _priceUnit = _defaultUnit(base);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Stok dan takaran resep dicatat dalam satuan ini. Satuan beli '
            'seperti kg, liter, atau rak diubah otomatis.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _minStock,
            keyboardType: number,
            decoration: InputDecoration(
              labelText: 'Stok minimum (opsional)',
              suffixText: unit,
              helperText: 'Di bawah angka ini bahan ditandai menipis.',
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Stok dan harga awal'),
          const SizedBox(height: 4),
          const Text(
            'Isi jika bahannya sudah ada sebelum memakai aplikasi. Tanpa '
            'stok, cukup isi harga sebagai perkiraan.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _openingQty,
            keyboardType: number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Stok awal (opsional)',
              suffixText: unit,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: const [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Harga beli',
                    prefixText: 'Rp ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_baseUnit),
                  initialValue: _priceUnit.name,
                  decoration: const InputDecoration(labelText: 'per'),
                  items: [
                    for (final option in unitOptionsFor(_baseUnit))
                      DropdownMenuItem(
                        value: option.name,
                        child: Text('1 ${option.name}'),
                      ),
                  ],
                  onChanged: (name) => setState(() {
                    _priceUnit = unitOptionsFor(_baseUnit)
                        .firstWhere((o) => o.name == name);
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InfoBox(hint, kind: hintKind),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan bahan'),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
    ),
  );
}
