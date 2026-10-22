import 'dart:async';
import 'dart:convert';

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
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../layout.dart';
import '../theme.dart';
import '../stock/ingredient_manage.dart' show editUnit;
import 'menu_drafts.dart';
import 'menu_labels.dart';

class _RecipeRow {
  _RecipeRow(this.ingredientId, [String qty = '', this.unit])
    : qty = TextEditingController(text: qty);

  final String ingredientId;
  final TextEditingController qty;

  /// Satuan takaran yang diketik; `null` = satuan dasar (FR-20.3).
  UnitOption? unit;
  List<UnitOption> units = const [];

  /// Takaran dalam satuan dasar bahan.
  Decimal? get qtyBase {
    final q = parseDecimalInput(qty.text);
    if (q == null) return null;
    return q * (unit?.factorToBase ?? Decimal.one);
  }
}

class _CostRow {
  _CostRow({
    String name = '',
    String amount = '',
    required this.costType,
    required this.basis,
  }) : name = TextEditingController(text: name),
       amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;
  final CostType costType;
  CostBasis basis;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

/// Biaya lain yang sering dipakai; nominalnya diisi sendiri.
const _costPresets = [
  ('Gas dan listrik', CostType.utilities, CostBasis.perBatch),
  ('Kemasan', CostType.other, CostBasis.perPcs),
  ('Penyusutan alat', CostType.depreciation, CostBasis.perBatch),
  ('Biaya lain', CostType.other, CostBasis.perBatch),
];

/// Menu baru atau ubah resep: takaran bahan, biaya lain, upah pemilik, harga
/// jual, dan HPP yang langsung terhitung (mockup `FormResep`, FR-2.1–2.7).
class MenuFormScreen extends ConsumerStatefulWidget {
  const MenuFormScreen({super.key, this.id, this.draftId});

  /// `null` = menu baru.
  final String? id;

  /// Lanjutkan draf menu baru ini (FR-20.1).
  final String? draftId;

  @override
  ConsumerState<MenuFormScreen> createState() => _MenuFormScreenState();
}

class _MenuFormScreenState extends ConsumerState<MenuFormScreen> {
  final _name = TextEditingController();
  final _yield = TextEditingController();
  final _shelfLife = TextEditingController();
  final _safetyStock = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _markup = TextEditingController();
  final _laborHours = TextEditingController();
  final _recipe = <_RecipeRow>[];
  final _costs = <_CostRow>[];

  /// `null` = belum dipilih; dipakai mode bawaan usaha.
  StockDeductMode? _mode;
  late bool _loading = widget.id != null || widget.draftId != null;
  var _saving = false;

  /// Draf otomatis (FR-20.1): id draf, isian saat dibuka (pembanding), dan
  /// draf perubahan yang belum dipakai (banner di Ubah resep).
  late final String _draftId =
      widget.id ??
      widget.draftId ??
      'baru-${DateTime.now().millisecondsSinceEpoch}';
  String? _baseline;
  MenuDraft? _pendingDraft;
  Timer? _draftTimer;
  var _saved = false;
  ScaffoldMessengerState? _messenger;
  GoRouter? _router;
  late final MenuDraftsNotifier _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(menuDraftsProvider.notifier);
    for (final c in [
      _name,
      _yield,
      _shelfLife,
      _safetyStock,
      _category,
      _price,
      _markup,
      _laborHours,
    ]) {
      c.addListener(_scheduleDraft);
    }
    if (widget.id != null) {
      _load(widget.id!);
    } else if (widget.draftId != null) {
      _openDraft(widget.draftId!);
    } else {
      _baseline = jsonEncode(_snapshot());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _router = GoRouter.maybeOf(context);
  }

  Future<void> _openDraft(String id) async {
    final draft = await _drafts.find(id);
    if (!mounted) return;
    if (draft != null) _apply(draft.data);
    setState(() => _loading = false);
    _baseline = jsonEncode(_snapshot());
    await _loadAllUnits();
  }

  /// Isian form apa adanya, untuk draf.
  Map<String, dynamic> _snapshot() => {
    'name': _name.text,
    'yield': _yield.text,
    'shelfLife': _shelfLife.text,
    'safetyStock': _safetyStock.text,
    'category': _category.text,
    'price': _price.text,
    'markup': _markup.text,
    'laborHours': _laborHours.text,
    'mode': _mode?.code,
    'recipe': [
      for (final r in _recipe)
        {
          'ingredientId': r.ingredientId,
          'qty': r.qty.text,
          'unitName': r.unit?.name,
          'unitFactor': r.unit?.factorToBase.toString(),
        },
    ],
    'costs': [
      for (final c in _costs)
        {
          'name': c.name.text,
          'amount': c.amount.text,
          'costType': c.costType.code,
          'basis': c.basis.code,
        },
    ],
  };

  void _apply(Map<String, dynamic> data) {
    String text(String key) => data[key] as String? ?? '';
    _name.text = text('name');
    _yield.text = text('yield');
    _shelfLife.text = text('shelfLife');
    _safetyStock.text = text('safetyStock');
    _category.text = text('category');
    _price.text = text('price');
    _markup.text = text('markup');
    _laborHours.text = text('laborHours');
    _mode = StockDeductMode.values
        .where((m) => m.code == data['mode'])
        .firstOrNull;
    for (final r in _recipe) {
      r.qty.dispose();
    }
    _recipe.clear();
    for (final raw in data['recipe'] as List? ?? const []) {
      final r = Map<String, dynamic>.from(raw as Map);
      final factor = Decimal.tryParse(r['unitFactor'] as String? ?? '');
      final name = r['unitName'] as String?;
      final row = _RecipeRow(
        r['ingredientId'] as String,
        r['qty'] as String? ?? '',
        name == null || factor == null
            ? null
            : UnitOption(name: name, factorToBase: factor),
      );
      _hook(row.qty);
      _recipe.add(row);
    }
    for (final c in _costs) {
      c.dispose();
    }
    _costs.clear();
    for (final raw in data['costs'] as List? ?? const []) {
      final c = Map<String, dynamic>.from(raw as Map);
      final row = _CostRow(
        name: c['name'] as String? ?? '',
        amount: c['amount'] as String? ?? '',
        costType: CostType.values.firstWhere(
          (t) => t.code == c['costType'],
          orElse: () => CostType.other,
        ),
        basis: CostBasis.values.firstWhere(
          (b) => b.code == c['basis'],
          orElse: () => CostBasis.perBatch,
        ),
      );
      _hook(row.name);
      _hook(row.amount);
      _costs.add(row);
    }
  }

  final _hooked = <TextEditingController>{};

  void _hook(TextEditingController c) {
    if (_hooked.add(c)) c.addListener(_scheduleDraft);
  }

  /// Simpan draf 1 detik setelah perubahan terakhir.
  void _scheduleDraft() {
    if (_loading || _saved || _baseline == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 1), _writeDraft);
  }

  /// `true` bila ada perubahan yang disimpan sebagai draf.
  bool _writeDraft() {
    if (_saved || _baseline == null) return false;
    final data = _snapshot();
    if (jsonEncode(data) == _baseline) return false;
    _drafts.save(
      MenuDraft(
        id: _draftId,
        productId: widget.id,
        savedAt: DateTime.now(),
        data: data,
      ),
    );
    return true;
  }

  Future<void> _load(String id) async {
    final input = await ref.read(productRepositoryProvider).inputOf(id);
    if (!mounted) return;
    setState(() {
      _name.text = input.name;
      _yield.text = formatDecimal(input.yieldQty);
      _shelfLife.text = input.shelfLifeDays?.toString() ?? '';
      final safety = input.safetyStock;
      _safetyStock.text = safety == null || safety == Decimal.zero
          ? ''
          : formatDecimal(safety);
      _category.text = input.category ?? '';
      _price.text = formatRupiahDigits(input.sellingPrice);
      _markup.text = input.targetMarkupPct == null
          ? ''
          : formatDecimal(input.targetMarkupPct!);
      _mode = input.stockDeductMode;
      for (final r in input.recipe) {
        final factor = r.unitFactor;
        final unit =
            r.unitName == null || factor == null || factor <= Decimal.zero
            ? null
            : UnitOption(name: r.unitName!, factorToBase: factor);
        final qty = unit == null
            ? r.qtyBase
            : divide(r.qtyBase, unit.factorToBase);
        _recipe.add(
          _RecipeRow(r.ingredientId, formatDecimal(qty, maxDecimals: 3), unit),
        );
      }
      for (final c in input.costs) {
        if (c.laborHours != null) {
          _laborHours.text = formatDecimal(c.laborHours!);
        } else {
          _costs.add(
            _CostRow(
              name: c.name,
              amount: formatRupiahDigits(c.amount),
              costType: c.costType,
              basis: c.basis,
            ),
          );
        }
      }
      _loading = false;
    });
    for (final r in _recipe) {
      _hook(r.qty);
    }
    for (final c in _costs) {
      _hook(c.name);
      _hook(c.amount);
    }
    _baseline = jsonEncode(_snapshot());
    final draft = await _drafts.find(_draftId);
    if (mounted && draft != null) setState(() => _pendingDraft = draft);
    await _loadAllUnits();
  }

  /// Banner "Ada perubahan belum disimpan" di Ubah resep.
  Future<void> _useDraft(bool use) async {
    final draft = _pendingDraft;
    if (draft == null) return;
    setState(() {
      _pendingDraft = null;
      if (use) _apply(draft.data);
    });
    if (!use) {
      await _drafts.remove(draft.id);
      return;
    }
    await _loadAllUnits();
  }

  /// Satuan semua baris resep sekaligus.
  Future<void> _loadAllUnits() async {
    final rows = [..._recipe];
    final stock = ref.read(stockRepositoryProvider);
    final units = await Future.wait([
      for (final r in rows) stock.unitOptions(r.ingredientId, forRecipe: true),
    ]);
    if (!mounted) return;
    setState(() {
      for (final (i, r) in rows.indexed) {
        r.units = units[i];
      }
    });
  }

  /// Satuan takaran yang bisa dipilih untuk baris resep (FR-20.3).
  Future<void> _loadUnits(_RecipeRow row) async {
    final units = await ref
        .read(stockRepositoryProvider)
        .unitOptions(row.ingredientId, forRecipe: true);
    if (!mounted) return;
    setState(() => row.units = units);
  }

  /// Pilih satuan takaran; satuan dapur yang belum punya konversi untuk
  /// bahan ini ditanya sekali ("1 sdm = … g").
  Future<void> _pickUnit(
    _RecipeRow row,
    IngredientView view,
    String name,
  ) async {
    final known = row.units
        .where((u) => normalizeUnitName(u.name) == normalizeUnitName(name))
        .firstOrNull;
    final base = known != null && known.factorToBase == Decimal.one
        ? null
        : known;
    if (known != null) {
      _switchUnit(row, base);
      return;
    }
    final saved = await editUnit(
      context,
      ref,
      view.ingredient,
      forRecipe: true,
      name: name.isEmpty ? null : name,
      askFactor: name.isNotEmpty,
    );
    if (saved == null || !mounted) return;
    await _loadUnits(row);
    _switchUnit(row, saved);
  }

  /// Ganti satuan sambil mempertahankan takaran dalam satuan dasar.
  void _switchUnit(_RecipeRow row, UnitOption? unit) {
    final base = row.qtyBase;
    setState(() {
      row.unit = unit;
      if (base != null) {
        row.qty.text = formatDecimal(
          unit == null ? base : divide(base, unit.factorToBase),
          maxDecimals: 3,
        );
      }
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // Keluar dari form dengan perubahan belum disimpan: jadi draf (FR-20.1).
    if (!_loading && _writeDraft()) {
      final router = _router;
      final path = widget.id == null
          ? '/menu/baru?draf=${Uri.encodeComponent(_draftId)}'
          : '/menu/${widget.id}/ubah';
      final messenger = _messenger;
      // Setelah frame ini: saat form ditutup karena seluruh aplikasi ditutup,
      // messenger sudah tidak ada dan snackbar dilewati.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger == null || !messenger.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Disimpan sebagai draf'),
            action: router == null
                ? null
                : SnackBarAction(
                    label: 'Lanjutkan',
                    onPressed: () => router.push(path),
                  ),
          ),
        );
      });
    }
    for (final c in [
      _name,
      _yield,
      _shelfLife,
      _safetyStock,
      _category,
      _price,
      _markup,
      _laborHours,
    ]) {
      c.dispose();
    }
    for (final r in _recipe) {
      r.qty.dispose();
    }
    for (final c in _costs) {
      c.dispose();
    }
    super.dispose();
  }

  Decimal? get _hours {
    final hours = parseDecimalInput(_laborHours.text);
    return hours == null || hours <= Decimal.zero ? null : hours;
  }

  /// HPP dari isian form dan data bahan terkini, dihitung saat diketik.
  ({HppBreakdown? hpp, HppStatus status, int? suggested, Decimal markup})
  _preview(Map<String, IngredientView> byId, Business? business) {
    final lines = <RecipeLine>[];
    for (final r in _recipe) {
      final v = byId[r.ingredientId];
      final qty = r.qtyBase;
      if (v == null || qty == null || qty <= Decimal.zero) continue;
      lines.add(
        RecipeLine(
          ingredientId: r.ingredientId,
          qtyPerBatch: qty,
          unitCost: v.avgUnitCost,
          isEstimate: v.ingredient.priceIsEstimate,
        ),
      );
    }
    final wage = business?.ownerHourlyWage;
    final hours = _hours;
    final yieldQty = parseDecimalInput(_yield.text);
    final markup =
        parseDecimalInput(_markup.text) ??
        dec(business?.defaultMarkupPct ?? 60);
    if (yieldQty == null || yieldQty <= Decimal.zero) {
      return (
        hpp: null,
        status: HppStatus.incomplete,
        suggested: null,
        markup: markup,
      );
    }
    final hpp = calculateHpp(
      lines: lines,
      yieldQty: yieldQty,
      otherCosts: [
        for (final c in _costs)
          OtherCost(
            name: c.name.text,
            amount: parseRupiahInput(c.amount.text) ?? 0,
            basis: c.basis,
          ),
        if (hours != null && wage != null)
          OtherCost(
            name: 'Upah pemilik',
            amount: laborCost(hours: hours, hourlyWage: wage),
            basis: CostBasis.perBatch,
          ),
      ],
    );
    final incomplete = lines.isEmpty || (hours != null && wage == null);
    final status = incomplete ? HppStatus.incomplete : hpp.status;
    return (
      hpp: hpp,
      status: status,
      suggested: status == HppStatus.incomplete
          ? null
          : suggestPriceByMarkup(
              hppPerPcs: hpp.hppPerPcs,
              markupPct: markup,
              rounding: business?.priceRounding ?? 500,
            ),
      markup: markup,
    );
  }

  Future<void> _addIngredient(List<IngredientView> all) async {
    final used = {for (final r in _recipe) r.ingredientId};
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IngredientPicker(
        options: [
          for (final v in all)
            if (!used.contains(v.ingredient.id)) v,
        ],
      ),
    );
    if (picked == null || !mounted) return;
    var id = picked;
    if (picked.startsWith(_IngredientPicker.newPrefix)) {
      final created = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _NewIngredientSheet(
          initialName: picked.substring(_IngredientPicker.newPrefix.length),
        ),
      );
      if (created == null || !mounted) return;
      id = created;
    }
    final row = _RecipeRow(id);
    setState(() => _recipe.add(row));
    await _loadUnits(row);
  }

  Future<void> _editWage(Business business) async {
    final wage = await showAppDialog<int>(
      context: context,
      builder: (_) => _WageDialog(initial: business.ownerHourlyWage),
    );
    if (wage == null || !mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(businessRepositoryProvider)
          .setOwnerHourlyWage(business.id, wage),
      'Upah per jam disimpan. HPP semua menu dihitung ulang.',
    );
  }

  Future<void> _save(Business? business) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    final name = _name.text.trim();
    final yieldQty = parseDecimalInput(_yield.text);
    if (name.isEmpty) return say('Nama menu belum diisi.');
    if (yieldQty == null || yieldQty <= Decimal.zero) {
      return say('Isi hasil per resep, mis. 20 pcs.');
    }
    if (business == null) return;
    final hours = _hours;
    final input = ProductInput(
      name: name,
      sellingPrice: parseRupiahInput(_price.text) ?? 0,
      yieldQty: yieldQty,
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      shelfLifeDays: int.tryParse(_shelfLife.text.trim()),
      safetyStock: parseDecimalInput(_safetyStock.text),
      stockDeductMode: _mode ?? business.stockDeductMode,
      targetMarkupPct: parseDecimalInput(_markup.text),
      recipe: [
        for (final r in _recipe)
          if ((r.qtyBase ?? Decimal.zero) > Decimal.zero)
            RecipeInput(
              ingredientId: r.ingredientId,
              qtyBase: r.qtyBase!,
              unitName: r.unit?.name,
              unitFactor: r.unit?.factorToBase,
            ),
      ],
      costs: [
        for (final c in _costs)
          if ((parseRupiahInput(c.amount.text) ?? 0) > 0)
            CostInput(
              name: c.name.text.trim().isEmpty ? 'Biaya lain' : c.name.text,
              costType: c.costType,
              basis: c.basis,
              amount: parseRupiahInput(c.amount.text)!,
            ),
        if (hours != null)
          CostInput(
            name: 'Upah pemilik',
            costType: CostType.labor,
            basis: CostBasis.perBatch,
            laborHours: hours,
          ),
      ],
    );
    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      if (widget.id == null) {
        final id = await repo.createProduct(business.id, input);
        _saved = true;
        await _drafts.remove(_draftId);
        if (!mounted) return;
        context.pushReplacement('/menu/$id');
      } else {
        await repo.updateProduct(widget.id!, input);
        _saved = true;
        await _drafts.remove(_draftId);
        if (!mounted) return;
        context.pop();
      }
      say('$name disimpan.');
    } catch (error) {
      say('Gagal menyimpan: $error');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.id == null ? 'Menu baru' : 'Ubah resep';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    final business = ref.watch(businessProvider).value;
    final byId = {for (final v in ingredients) v.ingredient.id: v};
    final preview = _preview(byId, business);
    final mode =
        _mode ?? business?.stockDeductMode ?? StockDeductMode.onProduction;
    const number = TextInputType.numberWithOptions(decimal: true);
    final (statusLabel, statusKind) = hppStatusPill(preview.status);
    final hpp = preview.hpp;
    for (final r in _recipe) {
      _hook(r.qty);
    }
    for (final c in _costs) {
      _hook(c.name);
      _hook(c.amount);
    }
    // Perubahan lewat pilihan (mode, satuan, baris) juga masuk draf.
    _scheduleDraft();
    final pending = _pendingDraft;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: readablePadding(
          context,
          const EdgeInsets.fromLTRB(20, 4, 20, 24),
        ),
        children: [
          if (pending != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ada perubahan belum disimpan dari '
                    '${formatShortDate(pending.savedAt)} '
                    '${formatTime(pending.savedAt)}.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => _useDraft(false),
                        child: const Text('Buang draf'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: () => _useDraft(true),
                        child: const Text('Pakai draf'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nama menu'),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _yield,
                  keyboardType: number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Hasil per resep',
                    suffixText: 'pcs',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _shelfLife,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Umur simpan',
                    suffixText: 'hari',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Kategori (opsional)',
              hintText: 'mis. Kue kering',
            ),
          ),
          const SizedBox(height: 16),
          const _Label('Mode stok'),
          Wrap(
            spacing: 8,
            children: [
              for (final m in StockDeductMode.values)
                ChoicePill(
                  label: modeLabel(m),
                  selected: mode == m,
                  onSelected: () => setState(() => _mode = m),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mode == StockDeductMode.onProduction
                ? 'Bahan dipotong saat produksi dicatat; hasilnya masuk stok '
                      'menu dan dijual dari stok itu.'
                : 'Dibuat sesuai pesanan; bahan dipotong saat pesanan selesai, '
                      'tanpa stok menu.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (mode == StockDeductMode.onProduction) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _safetyStock,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Stok jaga (opsional)',
                suffixText: 'pcs',
                helperText:
                    'Jumlah pcs yang ingin selalu tersedia di etalase. Ikut '
                    'dihitung di daftar belanja.',
                helperMaxLines: 3,
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('Bahan per resep'),
          const SizedBox(height: 8),
          if (_recipe.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, row) in _recipe.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _recipeRow(row, byId[row.ingredientId]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _addIngredient([
              for (final v in ingredients)
                if (!v.isArchived) v,
            ]),
            icon: const Icon(Icons.add),
            label: const Text('Tambah bahan'),
          ),
          const SizedBox(height: 24),
          SectionTitle(
            'Biaya lain',
            trailing: PopupMenuButton<int>(
              tooltip: 'Tambah biaya',
              onSelected: (i) => setState(() {
                final (name, type, basis) = _costPresets[i];
                _costs.add(
                  _CostRow(
                    name: i == _costPresets.length - 1 ? '' : name,
                    costType: type,
                    basis: basis,
                  ),
                );
              }),
              itemBuilder: (_) => [
                for (final (i, preset) in _costPresets.indexed)
                  PopupMenuItem(value: i, child: Text(preset.$1)),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: AppColors.primary),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Tambah biaya',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final row in _costs) ...[
                  _costRow(row),
                  const Divider(height: 1),
                ],
                _laborRow(business),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Harga jual'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: const [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Harga jual per pcs',
                    prefixText: 'Rp ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _markup,
                  keyboardType: number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Target markup',
                    suffixText: '%',
                    hintText: business == null
                        ? null
                        : formatDecimal(dec(business.defaultMarkupPct)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (preview.suggested != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saran ${formatRupiah(preview.suggested!)} '
                    '(markup ${formatDecimal(preview.markup)}%)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _price.text = formatRupiahDigits(preview.suggested!),
                  ),
                  child: const Text('Pakai'),
                ),
              ],
            )
          else
            const InfoBox(
              'Saran harga muncul setelah HPP lengkap: semua bahan punya '
              'harga dan upah per jam sudah diisi.',
            ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        above: Row(
          children: [
            const Expanded(
              child: Text(
                'HPP per pcs',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    hpp == null || _recipe.isEmpty
                        ? '—'
                        : formatRupiah(toRupiah(hpp.hppPerPcs)) +
                              (preview.status == HppStatus.incomplete
                                  ? '+'
                                  : ''),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusPill(statusLabel, kind: statusKind),
                ],
              ),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: _saving ? null : () => _save(business),
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ),
    );
  }

  Widget _recipeRow(_RecipeRow row, IngredientView? v) {
    final unit = v?.ingredient.unitLabel ?? '';
    final avg = v?.avgUnitCost;
    final (note, color) = v == null
        ? ('Memuat…', AppColors.textMuted)
        : avg == null
        ? ('Belum ada harga', AppColors.warning)
        : v.ingredient.priceIsEstimate
        ? ('Harga perkiraan ${formatUnitPrice(avg, unit)}', AppColors.warning)
        : (
            '${formatUnitPrice(avg, unit)} · stok ${formatQty(v.stock, unit)}',
            AppColors.textMuted,
          );
    final base = row.qtyBase;
    final converted = row.unit != null && base != null && v != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v?.ingredient.name ?? '…',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(note, style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: row.qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '0',
                  ),
                ),
              ),
              if (v == null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(unit),
                )
              else
                _unitMenu(row, v),
              IconButton(
                tooltip: 'Hapus dari resep',
                onPressed: () => setState(() {
                  _recipe.remove(row);
                  row.qty.dispose();
                }),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          if (converted)
            Text(
              [
                '= ${formatQty(base, unit)}',
                if (avg != null)
                  '${formatRupiah(toRupiah(base * avg))} per resep',
              ].join(' · '),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  /// Pilihan satuan takaran: satuan dasar, satuan bahan ini, dan satuan dapur
  /// (sdt, sdm, gelas) yang ditanya konversinya bila belum ada (FR-20.3).
  Widget _unitMenu(_RecipeRow row, IngredientView v) {
    final names = [
      for (final u in row.units) u.name,
      for (final k in kitchenUnits)
        if (!row.units.any((u) => normalizeUnitName(u.name) == k)) k,
    ];
    final current = row.unit?.name ?? v.ingredient.unitLabel;
    return PopupMenuButton<String>(
      tooltip: 'Satuan takaran',
      onSelected: (name) => _pickUnit(row, v, name),
      itemBuilder: (_) => [
        for (final n in names)
          PopupMenuItem(
            value: n,
            child: Text(
              row.units.any((u) => u.name == n) ? n : '$n (isi konversi)',
            ),
          ),
        const PopupMenuItem(value: '', child: Text('+ Satuan resep lain')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _costRow(_CostRow row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Nama biaya',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: TextField(
                  controller: row.amount,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: const [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: 'Rp ',
                    hintText: '0',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hapus biaya',
                onPressed: () => setState(() {
                  _costs.remove(row);
                  row.dispose();
                }),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (basis, label) in const [
                (CostBasis.perBatch, 'per resep'),
                (CostBasis.perPcs, 'per pcs'),
              ])
                ChoicePill(
                  label: label,
                  selected: row.basis == basis,
                  onSelected: () => setState(() => row.basis = basis),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _laborRow(Business? business) {
    final wage = business?.ownerHourlyWage;
    final hours = _hours;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upah pemilik',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  wage == null
                      ? 'Upah per jam belum diisi'
                      : hours == null
                      ? '× ${formatRupiah(wage)}/jam dari pengaturan'
                      : '× ${formatRupiah(wage)}/jam = '
                            '${formatRupiah(laborCost(hours: hours, hourlyWage: wage))}',
                  style: TextStyle(
                    fontSize: 12,
                    color: wage == null && hours != null
                        ? AppColors.warning
                        : AppColors.textMuted,
                  ),
                ),
                if (business != null)
                  GestureDetector(
                    onTap: () => _editWage(business),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        wage == null ? 'Isi upah per jam' : 'Ubah upah per jam',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _laborHours,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.end,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
                suffixText: 'jam',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilih bahan yang sudah ada atau buat bahan baru (FR-2.7).
class _IngredientPicker extends StatefulWidget {
  const _IngredientPicker({required this.options});

  /// Hasil pop untuk "bahan baru", diikuti nama yang sudah diketik.
  static const newPrefix = 'new:';

  final List<IngredientView> options;

  @override
  State<_IngredientPicker> createState() => _IngredientPickerState();
}

class _IngredientPickerState extends State<_IngredientPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final shown = widget.options
        .where((v) => v.ingredient.name.toLowerCase().contains(query))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cari bahan',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(
                query.isEmpty
                    ? 'Bahan baru'
                    : 'Bahan baru "${_query.text.trim()}"',
              ),
              subtitle: const Text('Belum ada di daftar bahan'),
              onTap: () => Navigator.pop(
                context,
                '${_IngredientPicker.newPrefix}${_query.text.trim()}',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final v in shown)
                    ListTile(
                      title: Text(v.ingredient.name),
                      subtitle: Text(
                        '${formatUnitPrice(v.avgUnitCost, v.ingredient.unitLabel)}'
                        ' · stok ${formatQty(v.stock, v.ingredient.unitLabel)}',
                      ),
                      onTap: () => Navigator.pop(context, v.ingredient.id),
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

/// Bottom sheet bahan baru dari form resep, dengan stok awal atau harga
/// perkiraan (FR-2.7, FR-1.7). Mengembalikan id bahan yang dibuat.
class _NewIngredientSheet extends ConsumerStatefulWidget {
  const _NewIngredientSheet({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_NewIngredientSheet> createState() =>
      _NewIngredientSheetState();
}

class _NewIngredientSheetState extends ConsumerState<_NewIngredientSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  final _stock = TextEditingController();
  final _price = TextEditingController();
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
    _stock.dispose();
    _price.dispose();
    super.dispose();
  }

  Decimal? get _qty {
    final qty = parseDecimalInput(_stock.text);
    return qty == null || qty <= Decimal.zero ? null : qty;
  }

  Decimal? get _unitCost {
    final price = parseRupiahInput(_price.text);
    if (price == null || price <= 0) return null;
    return divide(rupiah(price), _priceUnit.factorToBase);
  }

  (String, StatusKind) get _hint {
    final unit = _baseUnit.code;
    final qty = _qty;
    final cost = _unitCost;
    if (cost == null) {
      return qty != null
          ? ('Stok awal perlu harga belinya.', StatusKind.danger)
          : (
              'Belum ada harga: HPP menu ini akan ditandai belum lengkap '
                  'sampai harga diisi atau belanja pertama dicatat.',
              StatusKind.warning,
            );
    }
    if (qty != null) {
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
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nama bahan belum diisi.')),
      );
      return;
    }
    if (qty != null && cost == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Isi harga beli untuk stok awal.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      final ingredient = await ref
          .read(stockRepositoryProvider)
          .createIngredient(
            businessId: business.id,
            name: name,
            baseUnit: _baseUnit,
            openingQty: qty,
            openingUnitCost: qty == null ? null : cost,
            estimatedUnitCost: qty == null ? cost : null,
          );
      if (mounted) Navigator.pop(context, ingredient.id);
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
            Text('Bahan baru', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.initialName.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nama bahan'),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextField(
              controller: _stock,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan dan pakai di resep'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WageDialog extends StatefulWidget {
  const _WageDialog({required this.initial});

  final int? initial;

  @override
  State<_WageDialog> createState() => _WageDialogState();
}

class _WageDialogState extends State<_WageDialog> {
  late final _wage = TextEditingController(
    text: formatRupiahDigits(widget.initial ?? 0),
  );

  @override
  void dispose() {
    _wage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wage = parseRupiahInput(_wage.text);
    return AlertDialog(
      title: const Text('Upah per jam pemilik'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dipakai untuk semua menu: jam kerja per resep × upah per jam '
            'masuk ke HPP.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wage,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            inputFormatters: const [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Upah per jam',
              prefixText: 'Rp ',
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
          onPressed: wage == null ? null : () => Navigator.pop(context, wage),
          child: const Text('Simpan'),
        ),
      ],
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
