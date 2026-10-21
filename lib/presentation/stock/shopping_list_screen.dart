import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/shopping_repository.dart';
import '../../domain/stock/units.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../theme.dart';

/// Rentang pesanan yang bisa dipilih (FR-12.1).
const shoppingRanges = [(1, 'Hari ini'), (3, '3 hari'), (7, '7 hari')];

/// Satuan bawaan yang sudah jelas sendiri, tanpa "× faktor".
const _plainUnits = {'kg', 'ons', 'liter', 'lusin', 'kodi'};

/// "2 pack × 200 g = 400 g", "1 kg", "2 pak" (FR-12.3).
String shoppingQtyLabel(ShoppingLine line) {
  final item = line.item;
  final qty = dec(item.qty);
  final text = formatQty(qty, item.unitName);
  final base = line.ingredient?.baseUnit.code;
  final factor = dec(item.factorToBase);
  if (base == null ||
      factor == Decimal.one ||
      _plainUnits.contains(item.unitName.toLowerCase())) {
    return text;
  }
  return '$text × ${formatQty(factor, base)} = ${formatQty(qty * factor, base)}';
}

/// Teks yang dibagikan ke WhatsApp atau aplikasi lain (FR-12.8).
String shoppingShareText(ShoppingListView view, String businessName) {
  final until = view.until;
  final lines = [
    '*Daftar belanja · $businessName*',
    if (until != null) 'Untuk pesanan s.d. ${_dayLabel(until)}',
    '',
    for (final l in view.todo)
      '☐ ${l.item.name} — ${shoppingQtyLabel(l)}'
          '${l.item.estimatedCost == null ? '' : ' (±${formatRupiah(l.item.estimatedCost!)})'}',
    for (final l in view.done) '☑ ${l.item.name} — ${shoppingQtyLabel(l)}',
    '',
    if (view.total > 0) 'Perkiraan total: ±${formatRupiah(view.total)}',
    'Dibuat dengan BuatUsaha',
  ];
  return lines.join('\n');
}

/// "Jumat, 24 Okt".
String _dayLabel(DateTime day) {
  final long = formatLongDate(day).split(' ');
  return '${long[0]} ${long[1]} ${long[2].substring(0, 3)}';
}

/// Bahan › Daftar belanja (FR-12, mockup `DaftarBelanja`).
class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  var _busy = false;

  ShoppingRepository get _repo => ref.read(shoppingRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureList());
  }

  /// Daftar baru langsung dihitung dari pesanan.
  Future<void> _ensureList() async {
    final business = await ref.read(currentBusinessProvider.future);
    final list = await _repo.activeList(business.id);
    if (list.computedAt == null) await _recalculate(list.id);
  }

  Future<void> _recalculate(String listId, {int? days}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.recalculate(listId, days: days);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(ShoppingListView view) async {
    final business = ref.read(businessProvider).value;
    await SharePlus.instance.share(
      ShareParams(
        text: shoppingShareText(view, business?.name ?? 'BuatUsaha'),
        subject: 'Daftar belanja',
      ),
    );
  }

  Future<void> _finish(ShoppingListView view) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selesai belanja?'),
        content: const Text(
          'Daftar ini ditutup. Daftar berikutnya dihitung baru dari pesanan '
          'saat itu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _repo.finish(view.list.id);
    Haptics.success();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _toggle(ShoppingLine line) async {
    if (line.recorded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sudah dicatat di belanja; ubah lewat belanja itu.'),
        ),
      );
      return;
    }
    Haptics.select();
    await _repo.setChecked(line.item.id, checked: !line.checked);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(activeShoppingListProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar belanja'),
        actions: [
          if (view != null) ...[
            IconButton(
              tooltip: 'Bagikan daftar',
              onPressed: () => _share(view),
              icon: const Icon(Icons.share_outlined),
            ),
            PopupMenuButton<void>(
              tooltip: 'Menu lainnya',
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => _finish(view),
                  child: const Text('Selesai belanja'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: view == null
          ? const SkeletonList(height: 72)
          : _Body(
              view: view,
              busy: _busy,
              onRange: (days) => _recalculate(view.list.id, days: days),
              onRecalculate: () => _recalculate(view.list.id),
              onToggle: _toggle,
              onEdit: (line) => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                backgroundColor: AppColors.background,
                builder: (_) => _EditSheet(line: line),
              ),
              onAdd: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                backgroundColor: AppColors.background,
                builder: (_) => _AddSheet(listId: view.list.id),
              ),
            ),
      bottomNavigationBar: view == null
          ? null
          : BottomActionBar(
              child: FilledButton(
                onPressed: view.toRecord.isEmpty
                    ? null
                    : () =>
                          context.push('/bahan/belanja?daftar=${view.list.id}'),
                child: Text(
                  view.toRecord.isEmpty
                      ? 'Centang yang sudah dibeli'
                      : 'Catat jadi belanja (${view.toRecord.length})',
                ),
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.view,
    required this.busy,
    required this.onRange,
    required this.onRecalculate,
    required this.onToggle,
    required this.onEdit,
    required this.onAdd,
  });

  final ShoppingListView view;
  final bool busy;
  final ValueChanged<int> onRange;
  final VoidCallback onRecalculate;
  final ValueChanged<ShoppingLine> onToggle;
  final ValueChanged<ShoppingLine> onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final todo = view.todo;
    final done = view.done;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (days, label) in shoppingRanges)
              ChoicePill(
                label: label,
                selected: view.list.rangeDays == days,
                onSelected: () => onRange(days),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _Summary(view: view, busy: busy, onRecalculate: onRecalculate),
        const SizedBox(height: 20),
        SectionTitle('Perlu dibeli (${todo.length})'),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (todo.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: InfoBox(
                    view.lines.isEmpty
                        ? 'Tidak ada yang perlu dibeli untuk pesanan '
                              '${_rangeLabel(view.list.rangeDays)}.'
                        : 'Semua sudah dicentang.',
                    kind: StatusKind.success,
                  ),
                ),
              for (final (i, line) in todo.indexed) ...[
                if (i > 0) const Divider(height: 1),
                StaggeredEntrance(
                  key: ValueKey(line.item.id),
                  index: i,
                  child: _Row(
                    line: line,
                    onToggle: () => onToggle(line),
                    onTap: () => onEdit(line),
                  ),
                ),
              ],
              const Divider(height: 1),
              TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Tambah barang'),
              ),
            ],
          ),
        ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionTitle('Sudah dibeli (${done.length})'),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, line) in done.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _Row(
                    line: line,
                    onToggle: () => onToggle(line),
                    onTap: line.recorded ? null : () => onEdit(line),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Jumlah = kebutuhan pesanan + stok minimum − stok sekarang, '
          'dibulatkan ke satuan beli. Barang lain (mis. plastik) tidak masuk '
          'stok bahan.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  static String _rangeLabel(int days) =>
      days == 1 ? 'hari ini' : '$days hari ke depan';
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.view,
    required this.busy,
    required this.onRecalculate,
  });

  final ShoppingListView view;
  final bool busy;
  final VoidCallback onRecalculate;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(fontSize: 13, color: AppColors.onPrimaryMuted);
    final until = view.until;
    final parts = [
      '${view.ingredientCount} bahan'
          '${view.otherCount == 0 ? '' : ' + ${view.otherCount} barang lain'}',
      if (until != null)
        'untuk ${view.list.orderCount} pesanan s.d. ${_dayLabel(until)}',
    ];
    final computed = view.list.computedAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Perkiraan belanja',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onPrimaryMuted,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                '±',
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(fontSize: 32, color: AppColors.onPrimary),
              ),
              Flexible(
                child: AnimatedRupiah(
                  view.total,
                  style: Theme.of(context).textTheme.displaySmall
                      ?.copyWith(fontSize: 32, color: AppColors.onPrimary),
                ),
              ),
            ],
          ),
          Text(parts.join(' · '), style: muted),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF8A5A40), height: 1),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            spacing: 8,
            children: [
              Text(
                computed == null
                    ? 'Belum dihitung'
                    : 'Dihitung ${_when(computed)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onPrimaryMuted,
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  foregroundColor: AppColors.onPrimary,
                  side: const BorderSide(color: AppColors.onPrimaryMuted),
                  shape: const StadiumBorder(),
                ),
                onPressed: busy ? null : onRecalculate,
                child: Text(busy ? 'Menghitung…' : 'Hitung ulang'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime at) {
    final local = at.toLocal();
    final days = DateUtils.dateOnly(DateTime.now())
        .difference(DateUtils.dateOnly(local))
        .inDays;
    final day = switch (days) {
      0 => 'hari ini',
      1 => 'kemarin',
      _ => formatShortDate(local),
    };
    return '$day ${formatTime(local)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.line, required this.onToggle, this.onTap});

  final ShoppingLine line;
  final VoidCallback onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    final checked = line.checked;
    final cost = item.estimatedCost;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (_) => onToggle(),
              semanticLabel: checked
                  ? 'Batalkan centang ${item.name}'
                  : 'Tandai ${item.name} sudah dibeli',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: checked ? AppColors.textMuted : AppColors.text,
                      decoration: checked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shoppingQtyLabel(line),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (!checked) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (line.isOther)
                          const StatusPill(
                            'Barang lain',
                            kind: StatusKind.neutral,
                          ),
                        if (item.forOrders)
                          const StatusPill(
                            'Untuk pesanan',
                            kind: StatusKind.neutral,
                          ),
                        if (item.belowMinimum)
                          const StatusPill(
                            'Di bawah minimum',
                            kind: StatusKind.warning,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (checked)
              Flexible(
                flex: 0,
                child: StatusPill(
                  line.recorded ? 'Tercatat' : 'Dicentang',
                  kind: line.recorded ? StatusKind.success : StatusKind.neutral,
                ),
              )
            else
              Text(
                cost == null
                    ? (line.isOther ? '—' : 'harga belum ada')
                    : '±${formatRupiah(cost)}',
                style: TextStyle(
                  fontSize: cost == null ? 12 : 14,
                  fontWeight: cost == null ? FontWeight.w500 : FontWeight.w700,
                  color: cost == null ? AppColors.textMuted : AppColors.text,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ubah jumlah dan satuan item, atau hapus dari daftar.
class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.line});

  final ShoppingLine line;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final _qty = TextEditingController(
    text: formatDecimal(dec(widget.line.item.qty), maxDecimals: 3),
  );
  List<UnitOption> _units = const [];
  late UnitOption _unit = UnitOption(
    name: widget.line.item.unitName,
    factorToBase: dec(widget.line.item.factorToBase),
  );

  @override
  void initState() {
    super.initState();
    final id = widget.line.item.ingredientId;
    if (id != null) {
      ref.read(stockRepositoryProvider).unitOptions(id).then((units) {
        if (!mounted) return;
        setState(() {
          _units = units;
          _unit = units.firstWhere(
            (u) => u.name == _unit.name,
            orElse: () => _unit,
          );
        });
      });
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Decimal get _value => parseDecimalInput(_qty.text) ?? Decimal.zero;

  void _step(int delta) {
    final next = _value + Decimal.fromInt(delta);
    if (next <= Decimal.zero) return;
    Haptics.select();
    setState(() => _qty.text = formatDecimal(next, maxDecimals: 3));
  }

  Future<void> _save() async {
    final qty = _value;
    if (qty <= Decimal.zero) return;
    await ref
        .read(shoppingRepositoryProvider)
        .updateItem(widget.line.item.id, qty, _unit);
    Haptics.success();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    Haptics.warning();
    await ref.read(shoppingRepositoryProvider).removeItem(widget.line.item.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ingredient = widget.line.ingredient;
    final base = ingredient?.baseUnit.code;
    final avg = ingredient?.avgUnitCost;
    final baseQty = _value * _unit.factorToBase;
    final hint = [
      if (base != null && _unit.factorToBase != Decimal.one)
        '= ${formatQty(baseQty, base)}',
      if (avg != null)
        'perkiraan ${formatRupiah((baseQty * dec(avg)).round().toBigInt().toInt())}',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.line.item.name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Kurangi',
                onPressed: () => _step(-1),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _qty,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Jumlah'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: 'Tambah',
                onPressed: () => _step(1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_units.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in _units)
                  ChoicePill(
                    label: u.isCustom && base != null
                        ? '${u.name} (${formatQty(u.factorToBase, base)})'
                        : u.name,
                    selected: u.name == _unit.name,
                    onSelected: () => setState(() => _unit = u),
                  ),
              ],
            ),
          ],
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              hint,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Simpan')),
          const SizedBox(height: 4),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _remove,
            child: const Text('Hapus dari daftar'),
          ),
        ],
      ),
    );
  }
}

/// Tambah bahan terdaftar atau barang lain (FR-12.6).
class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.listId});

  final String listId;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _addIngredient(String id) async {
    await ref.read(shoppingRepositoryProvider).addIngredient(widget.listId, id);
    Haptics.success();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addOther(String name) async {
    await ref.read(shoppingRepositoryProvider).addOther(widget.listId, name);
    Haptics.success();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final all = ref.watch(ingredientsProvider).value ?? const [];
    final shown = all
        .where(
          (v) => v.ingredient.name.toLowerCase().contains(query.toLowerCase()),
        )
        .take(6)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tambah barang',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cari bahan atau ketik nama barang',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, v) in shown.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      v.ingredient.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Text(
                      'stok ${formatQty(v.stock, v.ingredient.baseUnit.code)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    onTap: () => _addIngredient(v.ingredient.id),
                  ),
                ],
                if (query.isNotEmpty) ...[
                  if (shown.isNotEmpty) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      '+ Barang lain: "$query"',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Tidak masuk stok bahan'),
                    onTap: () => _addOther(query),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }
}
