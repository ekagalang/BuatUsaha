import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/stock_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../theme.dart';
import 'labels.dart';

/// Nama satuan jumlah yang sering dipakai (FR-20.3); bebas diketik sendiri.
const countUnitSuggestions = [
  'pcs',
  'butir',
  'lembar',
  'buah',
  'bungkus',
  'siung',
  'botol',
  'sachet',
];

String baseUnitKindLabel(BaseUnit unit) => switch (unit) {
  BaseUnit.g => 'Berat (g)',
  BaseUnit.ml => 'Volume (ml)',
  BaseUnit.pcs => 'Jumlah',
};

Widget _sheet(BuildContext context, List<Widget> children) => Padding(
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
      children: children,
    ),
  ),
);

const _muted = TextStyle(fontSize: 13, color: AppColors.textMuted);

/// Lembar Ubah bahan (FR-20.2): semua bisa diubah, termasuk cara hitung.
class EditIngredientSheet extends ConsumerStatefulWidget {
  const EditIngredientSheet({super.key, required this.ingredient});

  final Ingredient ingredient;

  @override
  ConsumerState<EditIngredientSheet> createState() =>
      _EditIngredientSheetState();
}

class _EditIngredientSheetState extends ConsumerState<EditIngredientSheet> {
  late final _name = TextEditingController(text: widget.ingredient.name);
  late final _count = TextEditingController(
    text: widget.ingredient.countUnit ?? '',
  );
  late final _min = TextEditingController(
    text: widget.ingredient.minStock == 0
        ? ''
        : formatDecimal(dec(widget.ingredient.minStock), maxDecimals: 3),
  );
  late var _category = widget.ingredient.category;
  late var _base = widget.ingredient.baseUnit;
  var _minEdited = false;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _min.dispose();
    super.dispose();
  }

  String get _unitLabel => _base == BaseUnit.pcs
      ? (_count.text.trim().isEmpty ? 'pcs' : _count.text.trim())
      : _base.code;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nama bahan belum diisi.')),
      );
      return;
    }
    final repo = ref.read(stockRepositoryProvider);
    final id = widget.ingredient.id;
    Decimal? factor;
    if (_base != widget.ingredient.baseUnit && await repo.needsConversion(id)) {
      if (!mounted) return;
      factor = await showAppDialog<Decimal>(
        context: context,
        builder: (_) => ConversionDialog(
          ingredientName: name,
          from: widget.ingredient.unitLabel,
          to: _base == BaseUnit.pcs ? _unitLabel : _base.code,
        ),
      );
      if (factor == null) return;
    }
    setState(() => _saving = true);
    try {
      if (_base != widget.ingredient.baseUnit) {
        await repo.changeBaseUnit(id, _base, factor: factor);
      }
      await repo.updateIngredient(
        id,
        name: name,
        category: _category,
        minStock: _minEdited
            ? parseDecimalInput(_min.text) ?? Decimal.zero
            : null,
        countUnit: _base == BaseUnit.pcs ? _count.text : '',
      );
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('$name disimpan.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = _base != widget.ingredient.baseUnit;
    return _sheet(context, [
      Text('Ubah bahan', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nama bahan'),
      ),
      const SizedBox(height: 12),
      const Text('Kategori', style: _muted),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in IngredientCategory.values)
            ChoicePill(
              label: categoryLabel(c),
              selected: _category == c,
              onSelected: () => setState(() => _category = c),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('Dihitung dalam', style: _muted),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final u in BaseUnit.values)
            ChoicePill(
              label: baseUnitKindLabel(u),
              selected: _base == u,
              onSelected: () => setState(() => _base = u),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        changed
            ? 'Stok, harga, belanja, dan resep dikonversi saat disimpan. '
                  'Bila sudah ada stok atau riwayat, ditanya dulu 1 '
                  '${widget.ingredient.unitLabel} = berapa $_unitLabel.'
            : 'Bisa diganti kapan saja.',
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      if (_base == BaseUnit.pcs) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _count,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nama satuan',
            hintText: 'pcs',
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in countUnitSuggestions)
              ChoicePill(
                label: u,
                selected: _unitLabel == u,
                onSelected: () => setState(() => _count.text = u),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _min,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _minEdited = true,
        decoration: InputDecoration(
          labelText: 'Stok minimum',
          suffixText: changed ? null : _unitLabel,
          helperText: changed
              ? 'Ikut dikonversi; ubah setelah disimpan bila perlu.'
              : 'Isi 0 atau kosongkan bila tidak perlu dipantau.',
        ),
        enabled: !changed,
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
      ),
    ]);
  }
}

/// "1 butir = … g" saat cara hitung bahan diganti.
class ConversionDialog extends StatefulWidget {
  const ConversionDialog({
    super.key,
    required this.ingredientName,
    required this.from,
    required this.to,
  });

  final String ingredientName;
  final String from;
  final String to;

  @override
  State<ConversionDialog> createState() => _ConversionDialogState();
}

class _ConversionDialogState extends State<ConversionDialog> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = parseDecimalInput(_value.text);
    final valid = value != null && value > Decimal.zero;
    return AlertDialog(
      title: Text('1 ${widget.from} ${widget.ingredientName} = ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '1 ${widget.from} berisi',
              suffixText: widget.to,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Stok, harga rata-rata, riwayat, satuan beli, dan takaran resep '
            'dihitung ulang dengan angka ini.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
          onPressed: valid ? () => Navigator.pop(context, value) : null,
          child: const Text('Konversi'),
        ),
      ],
    );
  }
}

/// Isi stok awal (FR-20.6): jumlah dan harga per satuan; masuk nilai modal,
/// tidak dihitung laba.
class InitialStockDialog extends StatefulWidget {
  const InitialStockDialog({
    super.key,
    required this.unit,
    this.qty,
    this.unitCost,
  });

  final String unit;
  final Decimal? qty;
  final Decimal? unitCost;

  @override
  State<InitialStockDialog> createState() => _InitialStockDialogState();
}

class _InitialStockDialogState extends State<InitialStockDialog> {
  late final _qty = TextEditingController(
    text: widget.qty == null || widget.qty == Decimal.zero
        ? ''
        : formatDecimal(widget.qty!, maxDecimals: 3),
  );
  late final _price = TextEditingController(
    text: widget.unitCost == null
        ? ''
        : formatDecimal(widget.unitCost!, maxDecimals: 2),
  );

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = parseDecimalInput(_qty.text);
    final price = parseDecimalInput(_price.text);
    final valid =
        qty != null &&
        qty >= Decimal.zero &&
        price != null &&
        price > Decimal.zero;
    return AlertDialog(
      title: const Text('Isi stok awal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Stok yang ada sekarang',
                suffixText: widget.unit,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Harga per ${widget.unit}',
                prefixText: 'Rp ',
                helperText: valid
                    ? 'Nilai modal ${formatRupiah(toRupiah(qty * price))}'
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Stok awal masuk nilai modal, tidak dihitung sebagai laba.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
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
          onPressed: valid ? () => Navigator.pop(context, (qty, price)) : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Pilihan saat opname/penyesuaian di bahan yang stoknya 0 dan belum punya
/// riwayat (FR-20.6). `true` = catat sebagai stok awal.
Future<bool?> askFirstStock(BuildContext context) => showAppDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Ini stok pertama?'),
    content: const Text(
      'Stok sekarang 0 dan belum ada riwayat. Catat sebagai stok awal supaya '
      'tidak terhitung laba.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Tetap opname'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Catat sebagai stok awal'),
      ),
    ],
  ),
);

class RemoveChoice {
  const RemoveChoice(
    this.action, {
    this.waste = false,
    this.fromRecipes = false,
  });

  final RemoveAction action;
  final bool waste;
  final bool fromRecipes;
}

/// Dialog Arsipkan/Hapus bahan atau menu: setiap akibat jadi pilihan
/// (FR-20.2, FR-20.4). [recipeMenus] hanya untuk bahan.
class RemoveDialog extends StatefulWidget {
  const RemoveDialog({
    super.key,
    required this.name,
    required this.hasHistory,
    required this.initial,
    this.historyText,
    this.stockText,
    this.wasteText = 'Catat sisa sebagai rusak (masuk rugi bahan)',
    this.keepText = 'Biarkan, tetap dihitung di nilai modal',
    this.recipeMenus = const [],
    this.warning,
  });

  final String name;
  final bool hasHistory;
  final RemoveAction initial;
  final String? historyText;

  /// Mis. "Sisa stok 1.000 g (Rp33.000)"; `null` = tanpa stok.
  final String? stockText;
  final String wasteText;
  final String keepText;
  final List<String> recipeMenus;
  final String? warning;

  @override
  State<RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<RemoveDialog> {
  late var _action = widget.initial;
  var _waste = false;
  var _fromRecipes = true;

  Widget _choices<T>(
    T group,
    ValueChanged<T> onChanged,
    List<(T, String, String?)> options,
  ) => RadioGroup<T>(
    groupValue: group,
    onChanged: (v) => setState(() => onChanged(v as T)),
    child: Column(
      children: [
        for (final (value, title, subtitle) in options)
          RadioListTile<T>(
            value: value,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final permanent = !widget.hasHistory && _action == RemoveAction.delete;
    return AlertDialog(
      title: Text(
        widget.hasHistory
            ? '${widget.name} sudah punya riwayat'
            : 'Hapus ${widget.name}?',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.historyText != null)
              Text(widget.historyText!, style: _muted),
            if (widget.hasHistory)
              _choices(_action, (v) => _action = v, [
                (
                  RemoveAction.archive,
                  'Arsipkan (disarankan)',
                  'Disembunyikan, bisa dipulihkan dari saringan Diarsipkan.',
                ),
                (
                  RemoveAction.delete,
                  'Hapus',
                  'Tidak tampil lagi; laporan lama tetap memakai namanya.',
                ),
              ])
            else
              const Text(
                'Belum ada transaksi. Dihapus permanen.',
                style: _muted,
              ),
            if (widget.warning != null) ...[
              const SizedBox(height: 8),
              InfoBox(widget.warning!, kind: StatusKind.warning),
            ],
            if (widget.stockText != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.stockText!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              _choices(_waste, (v) => _waste = v, [
                (false, widget.keepText, null),
                (true, widget.wasteText, null),
              ]),
            ],
            if (widget.recipeMenus.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Dipakai di resep ${widget.recipeMenus.join(', ')}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              _choices(_fromRecipes, (v) => _fromRecipes = v, [
                (true, 'Hapus juga dari resep (HPP dihitung ulang)', null),
                (false, 'Biarkan di resep (pakai harga terakhir)', null),
              ]),
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
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: _action == RemoveAction.delete
                ? AppColors.danger
                : null,
          ),
          onPressed: () => Navigator.pop(
            context,
            RemoveChoice(
              _action,
              waste: widget.stockText != null && _waste,
              fromRecipes: widget.recipeMenus.isNotEmpty && _fromRecipes,
            ),
          ),
          child: Text(
            permanent || _action == RemoveAction.delete ? 'Hapus' : 'Arsipkan',
          ),
        ),
      ],
    );
  }
}

/// Arsipkan/hapus bahan dari Detail bahan; mengembalikan `true` bila bahan
/// tidak tampil lagi (layar sebaiknya ditutup).
Future<bool> removeIngredientFlow(
  BuildContext context,
  WidgetRef ref,
  IngredientView view, {
  required RemoveAction initial,
}) async {
  final repo = ref.read(archiveRepositoryProvider);
  final usage = await repo.ingredientUsage(view.ingredient.id);
  if (!context.mounted) return false;
  final unit = view.ingredient.unitLabel;
  final choice = await showAppDialog<RemoveChoice>(
    context: context,
    builder: (_) => RemoveDialog(
      name: view.ingredient.name,
      hasHistory: usage.hasHistory,
      initial: usage.hasHistory ? initial : RemoveAction.delete,
      stockText: usage.stock > Decimal.zero
          ? 'Sisa stok ${formatQty(usage.stock, unit)} '
                '(${formatRupiah(usage.value)})'
          : null,
      recipeMenus: [for (final m in usage.menus) m.name],
    ),
  );
  if (choice == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.removeIngredient(
      view.ingredient.id,
      action: choice.action,
      wasteRemaining: choice.waste,
      removeFromRecipes: choice.fromRecipes,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          choice.action == RemoveAction.archive
              ? '${view.ingredient.name} diarsipkan.'
              : '${view.ingredient.name} dihapus.',
        ),
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
    return false;
  }
}

/// Dialog satuan baru atau ubah satuan: saran dari satuan yang pernah dipakai
/// dan tawaran nama yang mirip, tanpa memaksa (FR-20.3). Hasil: (nama, isi
/// dalam satuan dasar).
class UnitDialog extends ConsumerStatefulWidget {
  const UnitDialog({
    super.key,
    required this.ingredient,
    this.forRecipe = false,
    this.initialName,
    this.initialFactor,
    this.askFactor = false,
  });

  final Ingredient ingredient;
  final bool forRecipe;
  final String? initialName;
  final Decimal? initialFactor;

  /// Nama sudah pasti (satuan dapur): hanya isinya yang ditanya.
  final bool askFactor;

  @override
  ConsumerState<UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends ConsumerState<UnitDialog> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _factor = TextEditingController(
    text: widget.initialFactor == null
        ? ''
        : formatDecimal(widget.initialFactor!, maxDecimals: 3),
  );
  late final Future<List<String>> _library = ref
      .read(stockRepositoryProvider)
      .unitLibrary(widget.ingredient.businessId);
  String? _keptName;

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
    final unit = widget.ingredient.unitLabel;
    return AlertDialog(
      title: Text(
        widget.askFactor
            ? 'Berapa $unit 1 ${widget.initialName} ${widget.ingredient.name.toLowerCase()}?'
            : widget.initialName != null
            ? 'Ubah satuan ${widget.initialName}'
            : widget.forRecipe
            ? 'Satuan resep ${widget.ingredient.name}'
            : 'Satuan baru ${widget.ingredient.name}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.askFactor) ...[
              TextField(
                controller: _name,
                autofocus: widget.initialName == null,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nama satuan',
                  hintText: widget.forRecipe
                      ? 'mis. sdm, siung, genggam'
                      : 'mis. pack, dus, renceng',
                ),
              ),
              FutureBuilder<List<String>>(
                future: _library,
                builder: (context, snapshot) {
                  final library = snapshot.data ?? const <String>[];
                  final similar = library
                      .where(
                        (l) =>
                            l != name &&
                            name.isNotEmpty &&
                            normalizeUnitName(l) == normalizeUnitName(name),
                      )
                      .firstOrNull;
                  final suggestions = <String>{
                    for (final l in [
                      if (widget.forRecipe) ...kitchenUnits,
                      ...library,
                    ])
                      if (l.toLowerCase().contains(name.toLowerCase()) &&
                          normalizeUnitName(l) != normalizeUnitName(name))
                        l,
                  }.take(8).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (similar != null && _keptName != name) ...[
                        const SizedBox(height: 8),
                        InfoBox('Mirip satuan "$similar" yang sudah dipakai.'),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                              ),
                              onPressed: () =>
                                  setState(() => _name.text = similar),
                              child: Text('Pakai "$similar"'),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                              ),
                              onPressed: () => setState(() => _keptName = name),
                              child: Text('Tetap buat "$name"'),
                            ),
                          ],
                        ),
                      ],
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in suggestions)
                              ActionChip(
                                label: Text(s),
                                onPressed: () => setState(() => _name.text = s),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _factor,
              autofocus: widget.askFactor,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '1 ${name.isEmpty ? 'satuan' : name} berisi',
                suffixText: unit,
              ),
            ),
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
          onPressed: valid
              ? () => Navigator.pop(context, (name, factor))
              : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Buat atau ubah satuan bahan lalu simpan; mengembalikan satuannya.
Future<UnitOption?> editUnit(
  BuildContext context,
  WidgetRef ref,
  Ingredient ingredient, {
  bool forRecipe = false,
  String? name,
  Decimal? factor,
  bool askFactor = false,
}) async {
  final result = await showAppDialog<(String, Decimal)>(
    context: context,
    builder: (_) => UnitDialog(
      ingredient: ingredient,
      forRecipe: forRecipe,
      initialName: name,
      initialFactor: factor,
      askFactor: askFactor,
    ),
  );
  if (result == null) return null;
  final (unitName, unitFactor) = result;
  await ref
      .read(stockRepositoryProvider)
      .addCustomUnit(
        ingredient.id,
        unitName: unitName,
        factorToBase: unitFactor,
        forRecipe: forRecipe,
      );
  return UnitOption(
    name: unitName,
    factorToBase: unitFactor,
    isCustom: true,
    forRecipe: forRecipe,
  );
}

/// Kartu Satuan di Detail bahan (FR-20.3): satuan dasar, satuan beli, satuan
/// resep; bisa diubah, ditambah, dan satuan bawaan bisa disembunyikan.
class IngredientUnitsCard extends ConsumerWidget {
  const IngredientUnitsCard({super.key, required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(ingredientUnitsProvider(ingredient.id)).value ??
        const <IngredientUnit>[];
    final unit = ingredient.unitLabel;
    final hidden = {
      for (final r in rows)
        if (r.hidden) normalizeUnitName(r.unitName),
    };
    final custom = [
      for (final r in rows)
        if (!r.hidden) r,
    ];
    final builtIn = [
      for (final (name, factor) in builtInUnits(ingredient.baseUnit))
        if (!custom.any((r) => normalizeUnitName(r.unitName) == name))
          (name, factor),
    ];
    Widget pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.onPrimaryContainer,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Satuan'),
        const SizedBox(height: 4),
        Text('Stok dihitung dalam $unit.', style: _muted),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final r in custom)
                ListTile(
                  title: Text(r.unitName),
                  subtitle: Text(
                    '1 ${r.unitName} = '
                    '${formatQty(dec(r.factorToBase), unit)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      pill(r.forRecipe ? 'resep' : 'beli'),
                      IconButton(
                        tooltip: 'Sembunyikan ${r.unitName}',
                        icon: const Icon(Icons.visibility_off_outlined),
                        onPressed: () => ref
                            .read(stockRepositoryProvider)
                            .setUnitHidden(
                              ingredient.id,
                              r.unitName,
                              hidden: true,
                            ),
                      ),
                    ],
                  ),
                  onTap: () => editUnit(
                    context,
                    ref,
                    ingredient,
                    forRecipe: r.forRecipe,
                    name: r.unitName,
                    factor: dec(r.factorToBase),
                  ),
                ),
              for (final (name, factor) in builtIn)
                ListTile(
                  title: Text(
                    name,
                    style: TextStyle(
                      color: hidden.contains(name) ? AppColors.textMuted : null,
                    ),
                  ),
                  subtitle: Text(
                    'bawaan · 1 $name = $factor $unit'
                    '${hidden.contains(name) ? ' · disembunyikan' : ''}',
                  ),
                  trailing: TextButton(
                    onPressed: () => ref
                        .read(stockRepositoryProvider)
                        .setUnitHidden(
                          ingredient.id,
                          name,
                          hidden: !hidden.contains(name),
                        ),
                    child: Text(
                      hidden.contains(name) ? 'Tampilkan' : 'Sembunyikan',
                    ),
                  ),
                ),
              for (final r in rows)
                if (r.hidden &&
                    !builtInUnits(ingredient.baseUnit)
                        .any((b) => b.$1 == normalizeUnitName(r.unitName)))
                  ListTile(
                    title: Text(
                      r.unitName,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    subtitle: const Text('disembunyikan'),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(stockRepositoryProvider)
                          .setUnitHidden(
                            ingredient.id,
                            r.unitName,
                            hidden: false,
                          ),
                      child: const Text('Tampilkan'),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => editUnit(context, ref, ingredient),
                icon: const Icon(Icons.add),
                label: const Text('Satuan beli'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    editUnit(context, ref, ingredient, forRecipe: true),
                icon: const Icon(Icons.add),
                label: const Text('Satuan resep'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tombol Isi stok awal untuk bahan yang belum punya transaksi (FR-20.6).
class InitialStockCard extends ConsumerWidget {
  const InitialStockCard({super.key, required this.view});

  final IngredientView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = view.stock == Decimal.zero;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              empty ? 'Belum ada stok' : 'Stok awal',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Isi stok yang sudah ada di dapur sekarang. Stok awal masuk '
              'nilai modal, tidak dihitung sebagai laba.',
              style: _muted,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => setInitialStockFlow(context, ref, view),
              child: Text(empty ? 'Isi stok awal' : 'Ubah stok awal'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> setInitialStockFlow(
  BuildContext context,
  WidgetRef ref,
  IngredientView view, {
  Decimal? qty,
}) async {
  final result = await showAppDialog<(Decimal, Decimal)>(
    context: context,
    builder: (_) => InitialStockDialog(
      unit: view.ingredient.unitLabel,
      qty: qty ?? view.stock,
      unitCost: view.avgUnitCost,
    ),
  );
  if (result == null || !context.mounted) return;
  final (stock, price) = result;
  await runWithSnack(
    context,
    () => ref
        .read(stockRepositoryProvider)
        .setInitialStock(view.ingredient.id, qtyBase: stock, unitCost: price),
    'Stok awal disimpan.',
  );
}

/// Arsipkan/hapus menu dari Detail menu (FR-20.4); `true` bila menu tidak
/// tampil lagi.
Future<bool> removeProductFlow(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  required RemoveAction initial,
}) async {
  final repo = ref.read(archiveRepositoryProvider);
  final usage = await repo.productUsage(product.id);
  if (!context.mounted) return false;
  final choice = await showAppDialog<RemoveChoice>(
    context: context,
    builder: (_) => RemoveDialog(
      name: product.name,
      hasHistory: usage.hasHistory,
      initial: usage.hasHistory ? initial : RemoveAction.delete,
      historyText: usage.soldCount > 0
          ? 'Sudah terjual ${usage.soldCount} kali.'
          : null,
      warning: usage.openOrders.isEmpty
          ? null
          : 'Masih ada di ${usage.openOrders.length} pesanan yang belum '
                'selesai (${usage.openOrders.join(', ')}). Pesanan itu tetap '
                'berjalan sampai selesai.',
      stockText: usage.stock > Decimal.zero
          ? 'Sisa stok menu jadi ${formatDecimal(usage.stock)} pcs'
          : null,
      keepText: 'Biarkan, tetap bisa dijual lewat pesanan yang ada',
      wasteText: 'Catat sisa dibuang (masuk rugi produk)',
    ),
  );
  if (choice == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await repo.removeProduct(
      product.id,
      action: choice.action,
      wasteRemaining: choice.waste,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          choice.action == RemoveAction.archive
              ? '${product.name} diarsipkan.'
              : '${product.name} dihapus.',
        ),
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
    return false;
  }
}
