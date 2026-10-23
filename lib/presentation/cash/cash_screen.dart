import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/cash_repository.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../motion.dart';
import '../orders/order_form_screen.dart' show SummaryRow;
import '../layout.dart';
import '../theme.dart';
import 'cash_account_picker.dart';

String cashKindLabel(CashAccountKind kind) => switch (kind) {
  CashAccountKind.cash => 'Tunai',
  CashAccountKind.bank => 'Bank',
  CashAccountKind.ewallet => 'E-wallet',
};

String _monthLabel(DateTime d) =>
    formatLongDate(d).split(' ').skip(2).join(' ');

/// Laporan kas (FR-15.4): saldo per akun, masuk/keluar bulan ini, penjelasan
/// laba vs kas, dan mutasinya.
class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  var _month = DateTime(DateTime.now().year, DateTime.now().month);

  (DateTime, DateTime) get _range =>
      (_month, DateTime(_month.year, _month.month + 1));

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final period = ref.watch(cashPeriodProvider(range));
    final report = ref.watch(periodReportProvider(range)).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kas'),
        actions: [
          TextButton(
            onPressed: () => context.push('/laporan/kas/akun'),
            child: const Text('Atur akun'),
          ),
        ],
      ),
      body: period.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat kas: $e')),
        data: (p) => ListView(
          padding: readablePadding(
            context,
            const EdgeInsets.fromLTRB(20, 4, 20, 24),
          ),
          children: [
            _BalanceHero(period: p),
            const SizedBox(height: 16),
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
                    _monthLabel(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
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
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SummaryRow('Uang masuk', formatRupiah(p.inflow)),
                    SummaryRow('Uang keluar', formatRupiah(-p.outflow)),
                    SummaryRow(
                      'Kas bersih',
                      formatRupiah(p.net),
                      bold: true,
                      color: p.net >= 0 ? AppColors.success : AppColors.danger,
                    ),
                  ],
                ),
              ),
            ),
            if (report != null) ...[
              const SizedBox(height: 12),
              _ProfitVsCash(netProfit: report.netProfit, cashNet: p.net),
            ],
            const SizedBox(height: 16),
            const SectionTitle('Mutasi'),
            const SizedBox(height: 8),
            if (p.movements.isEmpty)
              const Text(
                'Belum ada uang masuk atau keluar di bulan ini.',
                style: TextStyle(color: AppColors.textMuted),
              )
            else
              for (final day in p.days)
                _DayGroup(
                  day: day,
                  movements: [
                    for (final m in p.movements)
                      if (DateUtils.isSameDay(m.at.toLocal(), day.day)) m,
                  ],
                  accounts: {
                    for (final b in p.balances) b.account.id: b.account,
                  },
                ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: AppColors.background,
            builder: (_) => const CashEntrySheet(),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Catat kas'),
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.period});

  final CashPeriod period;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saldo kas hari ini',
              style: TextStyle(color: AppColors.onPrimaryMuted),
            ),
            const SizedBox(height: 4),
            AnimatedRupiah(
              period.total,
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final b in period.balances)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.account.isActive
                            ? b.account.name
                            : '${b.account.name} (nonaktif)',
                        style: const TextStyle(color: AppColors.onPrimary),
                      ),
                    ),
                    Text(
                      formatRupiah(b.balance),
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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

class _ProfitVsCash extends StatelessWidget {
  const _ProfitVsCash({required this.netProfit, required this.cashNet});

  final int netProfit;
  final int cashNet;

  @override
  Widget build(BuildContext context) {
    const bullet = TextStyle(fontSize: 13, color: AppColors.textMuted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Kenapa laba beda dengan kas?'),
            const SizedBox(height: 8),
            SummaryRow('Laba bersih bulan ini', formatRupiah(netProfit)),
            SummaryRow('Kas bersih bulan ini', formatRupiah(cashNet)),
            SummaryRow('Selisih', formatRupiah(cashNet - netProfit)),
            const SizedBox(height: 8),
            const Text(
              '• DP dan pelunasan masuk kas saat dibayar; laba diakui saat '
              'pesanan selesai.',
              style: bullet,
            ),
            const Text(
              '• Belanja bahan keluar kas saat dibeli; HPP-nya baru dihitung '
              'saat menu terjual.',
              style: bullet,
            ),
            const Text(
              '• Modal masuk dan ambil pribadi mengubah kas tetapi bukan laba.',
              style: bullet,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayGroup extends ConsumerWidget {
  const _DayGroup({
    required this.day,
    required this.movements,
    required this.accounts,
  });

  final CashDay day;
  final List<CashMovement> movements;
  final Map<String, CashAccount> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatLongDate(day.day),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '+${formatRupiah(day.inflow)}  ${formatRupiah(-day.outflow)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final m in movements)
                InkWell(
                  onTap: m.entryId == null
                      ? null
                      : () => _void(context, ref, m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.label),
                              Text(
                                '${accounts[m.accountId]?.name ?? 'Akun'} · '
                                '${formatTime(m.at)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${m.amount > 0 ? '+' : ''}${formatRupiah(m.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: m.isTransfer
                                ? AppColors.textMuted
                                : m.amount >= 0
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _void(
    BuildContext context,
    WidgetRef ref,
    CashMovement m,
  ) async {
    final reason = await showAppDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Batalkan catatan kas ini?',
        message:
            '${m.label} ${formatRupiah(m.amount.abs())} tidak dihitung lagi.',
      ),
    );
    if (reason == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(cashRepositoryProvider)
          .voidEntry(m.entryId!, reason: reason),
      'Catatan kas dibatalkan.',
    );
  }
}

/// Lembar Catat kas (FR-15.3).
class CashEntrySheet extends ConsumerStatefulWidget {
  const CashEntrySheet({super.key});

  @override
  ConsumerState<CashEntrySheet> createState() => _CashEntrySheetState();
}

class _CashEntrySheetState extends ConsumerState<CashEntrySheet> {
  static const _kinds = [
    (CashEntryKind.capitalIn, 'Modal masuk'),
    (CashEntryKind.ownerDraw, 'Ambil pribadi'),
    (CashEntryKind.transfer, 'Pindah'),
    (CashEntryKind.adjustment, 'Koreksi saldo'),
  ];

  var _kind = CashEntryKind.capitalIn;
  String? _account;
  String? _toAccount;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  var _date = DateTime.now();
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(List<CashAccount> accounts) async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = parseRupiahInput(_amount.text);
    final account = _account ?? defaultCashAccountId(accounts.first.businessId);
    if (amount == null || (_kind != CashEntryKind.adjustment && amount <= 0)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Isi nominalnya dulu.')),
      );
      return;
    }
    final now = DateTime.now();
    final at = DateUtils.isSameDay(_date, now)
        ? now
        : DateTime(_date.year, _date.month, _date.day, 12);
    setState(() => _saving = true);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      final repo = ref.read(cashRepositoryProvider);
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();
      String done;
      if (_kind == CashEntryKind.adjustment) {
        final id = await repo.adjustTo(
          business.id,
          accountId: account,
          actual: amount,
          at: at,
          note: note,
        );
        done = id == null ? 'Saldo sudah sesuai.' : 'Saldo dikoreksi.';
      } else {
        await repo.addEntry(
          business.id,
          kind: _kind,
          accountId: account,
          toAccountId: _toAccount,
          amount: amount,
          occurredAt: at,
          note: note,
        );
        done =
            '${_kinds.firstWhere((k) => k.$1 == _kind).$2} '
            '${formatRupiah(amount)} dicatat.';
      }
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(cashAccountsProvider).value ?? const [];
    final transfer = _kind == CashEntryKind.transfer;
    final adjust = _kind == CashEntryKind.adjustment;
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
            Text('Catat kas', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (kind, label) in _kinds)
                  ChoicePill(
                    label: label,
                    selected: _kind == kind,
                    onSelected: () => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            CashAccountPicker(
              label: transfer ? 'Dari akun' : 'Akun',
              value: _account,
              onChanged: (id) => setState(() => _account = id),
            ),
            if (transfer) ...[
              const SizedBox(height: 12),
              CashAccountPicker(
                label: 'Ke akun',
                required: true,
                value: _toAccount,
                onChanged: (id) => setState(() => _toAccount = id),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: InputDecoration(
                labelText: adjust ? 'Saldo sebenarnya' : 'Nominal',
                prefixText: 'Rp ',
                helperText: adjust
                    ? 'Hitung uang di akun ini; selisihnya dicatat sebagai koreksi.'
                    : null,
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
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving || accounts.isEmpty
                  ? null
                  : () => _save(accounts),
              child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
