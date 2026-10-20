import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/expense_repository.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

/// Daftar dan form pengeluaran operasional per bulan (FR-7.3, FR-7.7).
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  var _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final range = (_month, DateTime(_month.year, _month.month + 1));
    final expenses = ref.watch(expensesProvider(range));
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Bulan sebelumnya',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  formatLongDate(_month).split(' ').skip(2).join(' '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Bulan berikutnya',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const InfoBox(
            'Belanja bahan dan biaya yang sudah masuk HPP (gas per resep, upah '
            'pemilik) tidak dicatat di sini supaya tidak terhitung dua kali.',
            kind: StatusKind.neutral,
          ),
          const SizedBox(height: 12),
          ...expenses.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text('Gagal memuat: $e')],
            data: (list) {
              final active = list.where((e) => e.expense.voidedAt == null);
              final total = active.fold(0, (s, e) => s + e.expense.amount);
              return [
                SectionTitle(
                  'Total bulan ini',
                  trailing: Text(
                    formatRupiah(total),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Belum ada pengeluaran bulan ini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, e) in list.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          _row(e),
                        ],
                      ],
                    ),
                  ),
              ];
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Catat pengeluaran'),
        ),
      ),
    );
  }

  Widget _row(ExpenseView e) {
    final x = e.expense;
    final voided = x.voidedAt != null;
    return ListTile(
      title: Text(
        '${e.category.name}${x.isMonthly ? ' · bulanan' : ''}',
        style: TextStyle(
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        [
          formatShortDate(x.spentAt),
          if (x.note != null) x.note!,
          if (voided) 'dibatalkan: ${x.voidReason}',
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatRupiah(x.amount),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: voided ? AppColors.textMuted : null,
            ),
          ),
          if (!voided)
            IconButton(
              tooltip: 'Batalkan pengeluaran',
              onPressed: () => _void(x),
              icon: const Icon(Icons.undo, size: 18),
            ),
        ],
      ),
    );
  }

  Future<void> _void(Expense x) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Batalkan pengeluaran ini?',
        message: 'Laporan laba dihitung ulang tanpa pengeluaran ini.',
        warning: closedDayWarning(ref.read(businessProvider).value, x.spentAt),
      ),
    );
    if (reason == null || !mounted) return;
    await runWithSnack(
      context,
      () =>
          ref.read(expenseRepositoryProvider).voidExpense(x.id, reason: reason),
      'Pengeluaran dibatalkan.',
    );
  }

  Future<void> _add() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ExpenseSheet(),
  );
}

/// Form pengeluaran; juga dibuka dari "Catat cepat" di Beranda.
class ExpenseSheet extends ConsumerStatefulWidget {
  const ExpenseSheet({super.key});

  @override
  ConsumerState<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<ExpenseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _categoryId;
  var _date = DateTime.now();
  var _monthly = false;
  var _saving = false;

  static const _monthlyByDefault = {'Sewa', 'Listrik bulanan', 'Gaji'};

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupiahInput(_amount.text);
    final messenger = ScaffoldMessenger.of(context);
    if (_categoryId == null || amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pilih kategori dan isi nominalnya.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      await ref
          .read(expenseRepositoryProvider)
          .addExpense(
            business.id,
            categoryId: _categoryId!,
            amount: amount,
            spentAt: _date,
            isMonthly: _monthly,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Pengeluaran ${formatRupiah(amount)} dicatat.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider).value ?? const [];
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
              'Catat pengeluaran',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  ChoicePill(
                    label: c.name,
                    selected: _categoryId == c.id,
                    onSelected: () => setState(() {
                      _categoryId = c.id;
                      _monthly = _monthlyByDefault.contains(c.name);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(now.year - 2),
                  lastDate: now,
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(formatLongDate(_date)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _monthly,
              onChanged: (v) => setState(() => _monthly = v),
              title: const Text('Pengeluaran bulanan'),
              subtitle: const Text(
                'Tidak dibebankan ke ringkasan harian, hanya laporan bulanan.',
              ),
            ),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'mis. ojek antar pesanan',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
