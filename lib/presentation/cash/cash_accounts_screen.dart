import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/cash_repository.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../orders/order_labels.dart' show methodLabel;
import '../theme.dart';
import 'cash_screen.dart' show cashKindLabel;

/// Atur akun kas (FR-15.1): nama, jenis, saldo awal, cara bayar yang masuk.
class CashAccountsScreen extends ConsumerWidget {
  const CashAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cashAccountsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Akun kas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const Text(
            'Pembayaran pesanan masuk ke akun sesuai cara bayarnya. Saldo '
            'awal diisi sekali, lalu saldo dihitung dari semua transaksi.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          for (final a in accounts)
            Card(
              child: ListTile(
                title: Text(a.isActive ? a.name : '${a.name} (nonaktif)'),
                subtitle: Text(
                  [
                    cashKindLabel(a.kind),
                    'saldo awal ${formatRupiah(a.openingBalance)}',
                    if (paymentMethodsOf(a).isNotEmpty)
                      'menerima ${paymentMethodsOf(a).map(methodLabel).join(', ')}',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, a),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: OutlinedButton.icon(
          onPressed: () => _open(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Tambah akun'),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, CashAccount? account) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppColors.background,
        builder: (_) => _AccountSheet(account: account),
      );
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.account});

  final CashAccount? account;

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _opening = TextEditingController(
    text: formatRupiahDigits(widget.account?.openingBalance ?? 0),
  );
  late var _kind = widget.account?.kind ?? CashAccountKind.bank;
  late var _methods = widget.account == null
      ? <PaymentMethod>{}
      : paymentMethodsOf(widget.account!);
  late DateTime? _openingAt = widget.account?.openingAt?.toLocal();
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      await ref
          .read(cashRepositoryProvider)
          .saveAccount(
            business.id,
            id: widget.account?.id,
            name: _name.text,
            kind: _kind,
            openingBalance: parseRupiahInput(_opening.text) ?? 0,
            openingAt: _openingAt,
            methods: _methods,
          );
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Akun disimpan.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e is ArgumentError ? '${e.message}' : 'Gagal: $e'),
        ),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
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
              account == null ? 'Akun baru' : 'Ubah akun',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama akun'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final k in CashAccountKind.values)
                  ChoicePill(
                    label: cashKindLabel(k),
                    selected: _kind == k,
                    onSelected: () => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Saldo awal',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _openingAt ?? now,
                  firstDate: DateTime(now.year - 3),
                  lastDate: now,
                  helpText: 'Saldo awal per tanggal',
                );
                if (picked != null) setState(() => _openingAt = picked);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(
                _openingAt == null
                    ? 'Saldo awal berlaku dari awal'
                    : 'Saldo awal per ${formatLongDate(_openingAt!)}',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Transaksi sebelum tanggal itu dianggap sudah termasuk saldo awal.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pembayaran yang masuk ke akun ini',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  FilterChip(
                    label: Text(methodLabel(m)),
                    selected: _methods.contains(m),
                    onSelected: (on) => setState(
                      () => _methods = on
                          ? {..._methods, m}
                          : ({..._methods}..remove(m)),
                    ),
                  ),
              ],
            ),
            if (account != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: account.isActive,
                title: const Text('Aktif'),
                subtitle: const Text(
                  'Akun nonaktif tidak muncul di pilihan; mutasi lamanya tetap '
                  'dihitung.',
                ),
                onChanged: (v) async {
                  await ref
                      .read(cashRepositoryProvider)
                      .setActive(account.id, active: v);
                  if (context.mounted) Navigator.pop(context);
                },
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
