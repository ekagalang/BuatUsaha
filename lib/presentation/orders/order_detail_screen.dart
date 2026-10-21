import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/orders/orders.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../documents/document_screens.dart';
import '../motion.dart';
import '../theme.dart';
import 'order_form_screen.dart';
import 'order_labels.dart';

/// Detail pesanan: pelanggan, item, potongan channel, laba, pembayaran,
/// produksi, pengingat, ubah status, batal, dan koreksi (FR-5.x, FR-9.4).
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(id));
    return order.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Gagal memuat pesanan: $e')),
      ),
      data: (view) => _Detail(view: view),
    );
  }
}

enum _Menu { edit, cancel, correct }

class _Detail extends ConsumerWidget {
  const _Detail({required this.view});

  final OrderView view;

  OrderRepository _repo(WidgetRef ref) => ref.read(orderRepositoryProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = view.order;
    final now = DateTime.now();
    final (status, kind) = orderStatusPill(view, now);
    final next = nextStatus(o.status);
    final completed = o.status == OrderStatus.completed;
    final business = ref.watch(businessProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(o.orderNo),
        actions: [
          if (o.status != OrderStatus.cancelled)
            IconButton(
              tooltip: 'Nota',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: business == null
                  ? null
                  : () => showReceiptSheet(context, ref, view, business),
            ),
          if (view.isOpen || (completed && o.voidedAt == null))
            PopupMenuButton<_Menu>(
              onSelected: (m) => switch (m) {
                _Menu.edit => context.push('/pesanan/${o.id}/ubah'),
                _Menu.cancel => _cancel(context, ref),
                _Menu.correct => _correct(context, ref),
              },
              itemBuilder: (_) => [
                if (view.isOpen) ...[
                  const PopupMenuItem(
                    value: _Menu.edit,
                    child: Text('Ubah pesanan'),
                  ),
                  const PopupMenuItem(
                    value: _Menu.cancel,
                    child: Text('Batalkan pesanan'),
                  ),
                ],
                if (completed)
                  const PopupMenuItem(
                    value: _Menu.correct,
                    child: Text('Koreksi: batalkan pesanan selesai'),
                  ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  view.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              StatusPill(status, kind: kind),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            o.type == OrderType.direct
                ? 'Penjualan langsung · ${formatLongDate(o.dueAt)} '
                      '${formatTime(o.dueAt)}'
                : '${formatLongDate(o.dueAt)} · ${formatTime(o.dueAt)} · '
                      '${o.fulfillment == Fulfillment.pickup ? 'ambil sendiri' : 'diantar'}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (view.customer?.phoneWa != null)
            Text(
              'WhatsApp ${view.customer!.phoneWa}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty)
            Text(
              'Alamat: ${o.deliveryAddress}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          Text(
            'Channel: ${channelName(view)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (o.note != null)
            Text(
              'Catatan: ${o.note}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          if (o.voidReason != null) ...[
            const SizedBox(height: 10),
            InfoBox(
              '${o.voidedAt != null ? 'Dikoreksi' : 'Dibatalkan'}: '
              '${o.voidReason}',
              kind: StatusKind.danger,
            ),
          ],
          if (view.isLate(now)) ...[
            const SizedBox(height: 10),
            const InfoBox(
              'Pesanan ini sudah lewat jadwal dan belum selesai.',
              kind: StatusKind.danger,
            ),
          ],
          const SizedBox(height: 16),
          _ItemsCard(view: view),
          const SizedBox(height: 16),
          _MoneyCard(view: view),
          const SizedBox(height: 16),
          _PaymentsCard(
            view: view,
            onAdd: () => _addPayment(context, ref),
            onVoid: (p) => _voidPayment(context, ref, p),
          ),
          if (view.isOpen) ...[
            const SizedBox(height: 16),
            _ProductionCard(view: view),
          ],
          if (view.reminders.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RemindersCard(view: view),
          ],
        ],
      ),
      bottomNavigationBar: next == null
          ? null
          : BottomActionBar(
              child: FilledButton(
                onPressed: () => _advance(context, ref, next),
                child: Text(switch (next) {
                  OrderStatus.inProgress => 'Mulai diproses',
                  OrderStatus.ready => 'Tandai siap',
                  _ => 'Selesaikan pesanan',
                }),
              ),
            ),
    );
  }

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    OrderStatus next,
  ) async {
    if (next != OrderStatus.completed) {
      await runWithSnack(
        context,
        () => _repo(ref).setStatus(view.order.id, next),
        'Status: ${statusLabel(next)}.',
      );
      return;
    }
    if (view.order.paymentStatus != PaymentStatus.paid) {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Belum lunas'),
          content: Text(
            'Sisa tagihan ${formatRupiah(view.remaining)}. Tetap selesaikan? '
            'Pengingat pelunasan akan muncul sampai lunas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Selesaikan'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    try {
      await _repo(ref).completeOrder(view.order.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesanan selesai; omzet dicatat hari ini.'),
          ),
        );
      }
    } on InsufficientProductStockException catch (e) {
      if (!context.mounted) return;
      final line = view.lines.firstWhere(
        (l) => e.shortages.containsKey(l.product.name),
        orElse: () => view.lines.first,
      );
      await showStockShortDialog(context, e, line.product.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref) async {
    final result = await showAppDialog<(int, PaymentMethod)>(
      context: context,
      builder: (_) => _PaymentDialog(remaining: view.remaining),
    );
    if (result == null || !context.mounted) return;
    final (amount, method) = result;
    await runWithSnack(
      context,
      () => _repo(ref).addPayment(
        view.order.id,
        amount: amount,
        method: method,
        kind: amount >= view.remaining
            ? PaymentKind.settlement
            : PaymentKind.dp,
      ),
      'Pembayaran ${formatRupiah(amount)} dicatat.',
    );
  }

  Future<void> _voidPayment(
    BuildContext context,
    WidgetRef ref,
    Payment p,
  ) async {
    final reason = await showAppDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: 'Batalkan pembayaran ini?',
        message: 'Sisa tagihan dan status bayar dihitung ulang.',
        warning: closedDayWarning(ref.read(businessProvider).value, p.paidAt),
      ),
    );
    if (reason == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => _repo(ref).voidPayment(p.id, reason: reason),
      'Pembayaran dibatalkan.',
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final result = await showAppDialog<_CancelResult>(
      context: context,
      builder: (_) => _CancelDialog(
        title: 'Batalkan pesanan?',
        message: 'Pengingatnya ikut dibatalkan.',
        paid: view.order.paidAmount,
        allowReturn: false,
      ),
    );
    if (result == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => _repo(ref).cancelOrder(
        view.order.id,
        reason: result.reason,
        refund: result.refund,
      ),
      'Pesanan dibatalkan.',
    );
  }

  Future<void> _correct(BuildContext context, WidgetRef ref) async {
    final result = await showAppDialog<_CancelResult>(
      context: context,
      builder: (_) => _CancelDialog(
        title: 'Batalkan pesanan selesai?',
        message: [
          'Omzet pesanan ini dikeluarkan dari laporan tanggal selesainya. '
              'Uang yang dikembalikan dicatat sebagai refund.',
          ?closedDayWarning(
            ref.read(businessProvider).value,
            view.order.completedAt!,
          ),
        ].join('\n\n'),
        paid: view.order.paidAmount,
        allowReturn: true,
      ),
    );
    if (result == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => _repo(ref).voidCompletedOrder(
        view.order.id,
        reason: result.reason,
        refund: result.refund,
        returnToStock: result.returnToStock,
      ),
      'Pesanan dikoreksi.',
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Item'),
            const SizedBox(height: 8),
            for (final l in view.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.item.qty} × ${l.product.name}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${formatRupiah(l.item.unitPrice)}/pcs · HPP '
                            '${formatRupiah(toRupiah(l.hppPerPcs))}'
                            '${l.item.hppPerPcsSnapshot == null ? ' (perkiraan)' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          if (l.hppStatus == HppStatus.incomplete)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: StatusPill(
                                'HPP belum lengkap',
                                kind: StatusKind.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      formatRupiah(l.item.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w600),
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

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context) {
    final o = view.order;
    final net = view.itemsRevenue - o.channelFee;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Tagihan dan laba'),
            const SizedBox(height: 8),
            SummaryRow('Subtotal', formatRupiah(o.subtotal)),
            if (o.discount > 0) SummaryRow('Diskon', formatRupiah(-o.discount)),
            if (o.shippingFee > 0)
              SummaryRow('Ongkir (bukan omzet)', formatRupiah(o.shippingFee)),
            SummaryRow('Total tagihan', formatRupiah(o.total), bold: true),
            const Divider(height: 16),
            SummaryRow('Omzet item', formatRupiah(view.itemsRevenue)),
            SummaryRow(
              'Potongan ${channelName(view)}',
              formatRupiah(-o.channelFee),
            ),
            SummaryRow('Omzet bersih', formatRupiah(net)),
            SummaryRow(
              'HPP${view.hasIncompleteHpp ? ' (belum lengkap)' : ''}',
              formatRupiah(-view.cogs),
            ),
            SummaryRow(
              o.status == OrderStatus.completed ? 'Laba' : 'Perkiraan laba',
              formatRupiah(view.profit),
              bold: true,
              color: view.profit >= 0 ? AppColors.success : AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({
    required this.view,
    required this.onAdd,
    required this.onVoid,
  });

  final OrderView view;
  final VoidCallback onAdd;
  final ValueChanged<Payment> onVoid;

  @override
  Widget build(BuildContext context) {
    final o = view.order;
    final canPay = o.status != OrderStatus.cancelled && view.remaining > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Pembayaran',
              trailing: StatusPill(
                paymentLabel(view),
                kind: switch (o.paymentStatus) {
                  PaymentStatus.paid => StatusKind.success,
                  PaymentStatus.partial => StatusKind.warning,
                  PaymentStatus.unpaid => StatusKind.danger,
                },
              ),
            ),
            const SizedBox(height: 8),
            if (view.payments.isEmpty)
              const Text(
                'Belum ada pembayaran.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            for (final p in view.payments)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${paymentKindLabel(p.kind)} · ${methodLabel(p.method)} · '
                      '${formatShortDate(p.paidAt)}'
                      '${p.voidedAt != null ? ' · dibatalkan' : ''}',
                      style: TextStyle(
                        decoration: p.voidedAt != null
                            ? TextDecoration.lineThrough
                            : null,
                        color: p.voidedAt != null ? AppColors.textMuted : null,
                      ),
                    ),
                  ),
                  Text(
                    formatRupiah(
                      p.kind == PaymentKind.refund ? -p.amount : p.amount,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (p.voidedAt == null)
                    IconButton(
                      tooltip: 'Batalkan pembayaran',
                      onPressed: () => onVoid(p),
                      icon: const Icon(Icons.undo, size: 18),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            if (canPay) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  'Catat bayar · sisa ${formatRupiah(view.remaining)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Produksi untuk pesanan ini (FR-4.3): pesanan jadi Diproses.
class _ProductionCard extends ConsumerWidget {
  const _ProductionCard({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = {
      for (final p in ref.watch(productsProvider).value ?? const [])
        p.product.id: p,
    };
    final made = <String, Decimal>{};
    for (final p in view.productions.where((p) => p.voidedAt == null)) {
      made.update(
        p.productId,
        (q) => q + dec(p.outputQty),
        ifAbsent: () => dec(p.outputQty),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Produksi'),
            const SizedBox(height: 8),
            for (final l in view.lines) ...[
              Builder(
                builder: (context) {
                  final p = products[l.product.id];
                  final done = made[l.product.id] ?? Decimal.zero;
                  final stock = p?.isReadyStock ?? false
                      ? ' · stok ${formatDecimal(p!.stock)}'
                      : '';
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l.product.name}: ${l.item.qty} pcs dipesan'
                          '${done > Decimal.zero ? ', ${formatDecimal(done)} sudah dibuat' : ''}'
                          '$stock',
                        ),
                      ),
                      TextButton(
                        onPressed: () => _produce(context, ref, l),
                        child: const Text('Catat'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _produce(
    BuildContext context,
    WidgetRef ref,
    OrderLine line,
  ) async {
    final yieldQty = dec(line.product.yieldQty);
    final suggested = divide(Decimal.fromInt(line.item.qty), yieldQty);
    final batch = await showAppDialog<Decimal>(
      context: context,
      builder: (_) => _BatchDialog(
        product: line.product.name,
        yieldQty: yieldQty,
        initial: suggested,
      ),
    );
    if (batch == null || !context.mounted) return;
    await runWithSnack(
      context,
      () => ref
          .read(productRepositoryProvider)
          .recordProduction(
            line.product.id,
            batchQty: batch,
            orderId: view.order.id,
          ),
      'Produksi ${formatDecimal(batch * yieldQty)} pcs dicatat.',
    );
  }
}

class _RemindersCard extends StatelessWidget {
  const _RemindersCard({required this.view});

  final OrderView view;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Pengingat'),
            const SizedBox(height: 8),
            for (final r in view.reminders)
              Text(
                '${formatShortDate(r.remindAt)} ${formatTime(r.remindAt)} · '
                '${switch (r.status) {
                  ReminderStatus.scheduled => 'terjadwal',
                  ReminderStatus.fired => 'sudah muncul',
                  ReminderStatus.cancelled => 'dibatalkan',
                }}',
                style: TextStyle(
                  color: r.status == ReminderStatus.scheduled
                      ? null
                      : AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.remaining});

  final int remaining;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(
    text: formatRupiahDigits(widget.remaining),
  );
  var _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseRupiahInput(_amount.text);
    return AlertDialog(
      title: const Text('Catat pembayaran'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            inputFormatters: const [RupiahInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Jumlah',
              prefixText: 'Rp ',
              helperText: 'Sisa tagihan ${formatRupiah(widget.remaining)}',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in PaymentMethod.values)
                ChoicePill(
                  label: methodLabel(m),
                  selected: _method == m,
                  onSelected: () => setState(() => _method = m),
                ),
            ],
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
          onPressed: amount == null || amount <= 0
              ? null
              : () => Navigator.pop(context, (amount, _method)),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _CancelResult {
  const _CancelResult(this.reason, this.refund, this.returnToStock);

  final String reason;
  final int refund;
  final bool returnToStock;
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({
    required this.title,
    required this.message,
    required this.paid,
    required this.allowReturn,
  });

  final String title;
  final String message;
  final int paid;
  final bool allowReturn;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  late final _refund = TextEditingController(
    text: formatRupiahDigits(widget.paid),
  );
  var _returnToStock = true;

  @override
  void dispose() {
    _reason.dispose();
    _refund.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Alasan'),
            ),
            if (widget.paid > 0) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _refund,
                keyboardType: TextInputType.number,
                inputFormatters: const [RupiahInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Uang dikembalikan',
                  prefixText: 'Rp ',
                  helperText: 'Sudah dibayar ${formatRupiah(widget.paid)}',
                ),
              ),
            ],
            if (widget.allowReturn)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _returnToStock,
                onChanged: (v) => setState(() => _returnToStock = v),
                title: const Text('Barang kembali ke stok menu jadi'),
                subtitle: Text(
                  _returnToStock
                      ? 'Menu ready stock bertambah lagi.'
                      : 'Dicatat dibuang sebagai kerugian.',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tidak'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: AppColors.danger,
          ),
          onPressed: reason.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  _CancelResult(
                    reason,
                    parseRupiahInput(_refund.text) ?? 0,
                    _returnToStock,
                  ),
                ),
          child: const Text('Batalkan'),
        ),
      ],
    );
  }
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({
    required this.product,
    required this.yieldQty,
    required this.initial,
  });

  final String product;
  final Decimal yieldQty;
  final Decimal initial;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  late final _batch = TextEditingController(
    text: formatDecimal(widget.initial, maxDecimals: 2),
  );

  @override
  void dispose() {
    _batch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batch = parseDecimalInput(_batch.text);
    final valid = batch != null && batch > Decimal.zero;
    return AlertDialog(
      title: Text('Produksi ${widget.product}'),
      content: TextField(
        controller: _batch,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Jumlah resep',
          suffixText: 'resep',
          helperText: valid
              ? 'Hasil ${formatDecimal(batch * widget.yieldQty)} pcs'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: valid ? () => Navigator.pop(context, batch) : null,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
