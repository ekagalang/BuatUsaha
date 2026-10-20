import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/day_close_repository.dart';
import '../../domain/costing/costing.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

String wasteReasonLabel(WasteReason r) => switch (r) {
  WasteReason.expired => 'Kedaluwarsa',
  WasteReason.damaged => 'Rusak',
  WasteReason.selfUse => 'Dipakai sendiri',
  WasteReason.other => 'Lainnya',
};

class _Entry {
  _Entry(this.leftover)
    : reason = leftover.expiredQty > Decimal.zero
          ? WasteReason.expired
          : WasteReason.damaged,
      // Sisa yang lewat umur simpan disarankan dibuang (FR-4.10).
      waste = leftover.expiredQty.floor().toBigInt().toInt();

  final Leftover leftover;
  int waste;
  WasteReason reason;

  int get max => leftover.stock.floor().toBigInt().toInt();
  Decimal get kept => leftover.stock - Decimal.fromInt(waste);
}

/// Tutup hari: sisa menu ready stock disimpan atau dibuang beserta alasannya
/// (FR-4.6–4.8, FR-4.10; mockup `TutupHari`).
class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final _entries = <String, _Entry>{};
  var _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final today = DateTime.now();
    final discards = [
      for (final e in _entries.values)
        if (e.waste > 0)
          DiscardInput(
            productId: e.leftover.product.id,
            qty: Decimal.fromInt(e.waste),
            reason: e.reason,
          ),
    ];
    final ok = await runWithSnack(context, () async {
      final business = await ref.read(currentBusinessProvider.future);
      await ref
          .read(dayCloseRepositoryProvider)
          .closeDay(business.id, today, discards);
    }, 'Tutup hari disimpan.');
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).maybePop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leftovers = ref.watch(leftoversProvider);
    final business = ref.watch(businessProvider).value;
    final today = DateTime.now();
    final closed =
        business?.lastClosedOn != null &&
        dayKey(today).compareTo(business!.lastClosedOn!) <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Tutup hari')),
      body: leftovers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat sisa menu: $e')),
        data: (list) {
          for (final l in list) {
            _entries.putIfAbsent(l.product.id, () => _Entry(l));
          }
          final entries = [for (final l in list) _entries[l.product.id]!];
          var loss = 0;
          var keptValue = 0;
          for (final e in entries) {
            loss += e.leftover.lossFor(Decimal.fromInt(e.waste));
            keptValue += e.leftover.lossFor(e.kept);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                formatLongDate(today),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              const Text(
                'Catat sisa menu ready stock. Yang disimpan tetap jadi stok '
                'untuk besok; yang dibuang dihitung sebagai rugi.',
              ),
              if (closed) ...[
                const SizedBox(height: 10),
                const InfoBox(
                  'Hari ini sudah ditutup. Sisa yang dicatat sekarang tetap '
                  'masuk ringkasan hari ini.',
                  kind: StatusKind.neutral,
                ),
              ],
              const SizedBox(height: 16),
              if (entries.isEmpty)
                const InfoBox(
                  'Tidak ada sisa menu ready stock hari ini.',
                  kind: StatusKind.success,
                ),
              for (final e in entries) ...[
                _EntryCard(entry: e, onChanged: () => setState(() {})),
                const SizedBox(height: 10),
              ],
              if (entries.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _Total(
                          'Rugi sisa hari ini',
                          formatRupiah(loss),
                          color: loss > 0 ? AppColors.danger : null,
                        ),
                        _Total('Nilai yang disimpan', formatRupiah(keptValue)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Jika dilewati, sisa dianggap disimpan dan bisa dicatat '
                'dibuang kapan saja dari detail menu.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan Tutup hari'),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onChanged});

  final _Entry entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = entry.leftover;
    final shelf = l.product.shelfLifeDays;
    final (shelfText, shelfKind) = l.expiredQty > Decimal.zero
        ? (
            '${formatDecimal(l.expiredQty)} pcs lewat umur simpan',
            StatusKind.danger,
          )
        : l.expiresTomorrowQty > Decimal.zero
        ? (
            '${formatDecimal(l.expiresTomorrowQty)} pcs habis besok',
            StatusKind.warning,
          )
        : (
            shelf == null ? 'Tanpa umur simpan' : 'Masih aman',
            StatusKind.success,
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: StatusPill(shelfText, kind: shelfKind)),
              ],
            ),
            Text(
              'Sisa ${formatDecimal(l.stock)} pcs · HPP '
              '${formatRupiah(toRupiah(l.avgCost))}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dibuang'),
                      Text(
                        'Disimpan: ${formatDecimal(entry.kept)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Kurangi yang dibuang',
                  onPressed: entry.waste > 0
                      ? () {
                          entry.waste--;
                          onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${entry.waste}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Tambah yang dibuang',
                  onPressed: entry.waste < entry.max
                      ? () {
                          entry.waste++;
                          onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (entry.waste > 0) ...[
              const SizedBox(height: 10),
              const Text(
                'Alasan dibuang',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in WasteReason.values)
                    ChoicePill(
                      label: wasteReasonLabel(r),
                      selected: entry.reason == r,
                      onSelected: () {
                        entry.reason = r;
                        onChanged();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Rugi: ${formatRupiah(l.lossFor(Decimal.fromInt(entry.waste)))}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}
