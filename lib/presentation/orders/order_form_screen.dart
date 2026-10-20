import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/db/decimal_convert.dart';
import '../../data/providers.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/orders/orders.dart';
import '../common/format.dart';
import '../common/rupiah_input.dart';
import '../common/widgets.dart';
import '../menu/menu_labels.dart';
import '../theme.dart';
import 'order_labels.dart';

class _ItemRow {
  _ItemRow(this.productId, {this.qty = 1, required int price})
    : price = TextEditingController(text: formatRupiahDigits(price));

  final String productId;
  int qty;
  final TextEditingController price;

  int get unitPrice => parseRupiahInput(price.text) ?? 0;
}

class _ReminderRow {
  _ReminderRow(this.input, {this.enabled = true});

  final ReminderInput input;
  bool enabled;
}

/// Pesanan baru / ubah pesanan (FR-5.1, FR-5.2, FR-5.8, FR-5.9, FR-6.1) dan
/// penjualan langsung (FR-5.7). Mockup `FormPesanan`.
class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({
    super.key,
    this.id,
    this.direct = false,
    this.initialDay,
  });

  /// `null` = pesanan baru.
  final String? id;

  /// Penjualan langsung: tanpa jadwal dan pengingat, langsung Selesai/Lunas.
  final bool direct;
  final DateTime? initialDay;

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  final _discount = TextEditingController();
  final _shipping = TextEditingController();
  final _fee = TextEditingController();
  final _paid = TextEditingController();
  final _items = <_ItemRow>[];
  final _reminders = <_ReminderRow>[];
  String? _channelId;
  var _feeEdited = false;
  var _fulfillment = Fulfillment.pickup;
  var _method = PaymentMethod.cash;
  late DateTime _date;
  var _time = const TimeOfDay(hour: 10, minute: 0);
  late bool _loading = widget.id != null || !widget.direct;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final base = widget.initialDay ?? DateTime.now();
    final today = DateTime.now();
    _date = DateTime(base.year, base.month, base.day);
    if (_date.isBefore(DateTime(today.year, today.month, today.day))) {
      _date = DateTime(today.year, today.month, today.day);
    }
    if (widget.id != null) {
      _load(widget.id!);
    } else if (!widget.direct) {
      _loadDefaults();
    }
  }

  Future<void> _loadDefaults() async {
    final business = await ref.read(currentBusinessProvider.future);
    final defaults = await ref
        .read(orderRepositoryProvider)
        .defaultReminders(business.id);
    if (!mounted) return;
    setState(() {
      _reminders.addAll([for (final r in defaults) _ReminderRow(r)]);
      _loading = false;
    });
  }

  Future<void> _load(String id) async {
    final repo = ref.read(orderRepositoryProvider);
    final view = await repo.loadOrder(id);
    final business = await ref.read(currentBusinessProvider.future);
    final defaults = await repo.defaultReminders(business.id);
    final autoFee = await repo.suggestedChannelFee(
      view.order.channelId,
      view.itemsRevenue,
    );
    if (!mounted) return;
    final o = view.order;
    final due = o.dueAt.toLocal();
    final saved = OrderRepository.remindersOf(view);
    final active = view.reminders
        .where((r) => r.status != ReminderStatus.cancelled)
        .length;
    setState(() {
      _name.text = view.customer?.name ?? '';
      _phone.text = view.customer?.phoneWa ?? '';
      _address.text = o.deliveryAddress ?? '';
      _note.text = o.note ?? '';
      _discount.text = formatRupiahDigits(o.discount);
      _shipping.text = formatRupiahDigits(o.shippingFee);
      _channelId = o.channelId;
      _fee.text = formatRupiahDigits(o.channelFee);
      // Potongan yang sama dengan hitungan otomatis tetap ikut berubah.
      _feeEdited = o.channelFee != autoFee;
      _fulfillment = o.fulfillment;
      _date = DateTime(due.year, due.month, due.day);
      _time = TimeOfDay(hour: due.hour, minute: due.minute);
      for (final l in view.lines) {
        _items.add(
          _ItemRow(l.product.id, qty: l.item.qty, price: l.item.unitPrice),
        );
      }
      // Pengingat tersimpan; pengingat bawaan yang tidak ada tampil nonaktif.
      _reminders.addAll([for (final r in saved) _ReminderRow(r)]);
      for (final d in defaults) {
        final exists = saved.any(
          (r) =>
              r.kind == d.kind &&
              (r.kind != ReminderKind.dayBefore || r.time == d.time) &&
              (r.kind != ReminderKind.beforeDue || r.minutes == d.minutes),
        );
        if (!exists) _reminders.add(_ReminderRow(d, enabled: active == 0));
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _address,
      _note,
      _discount,
      _shipping,
      _fee,
      _paid,
    ]) {
      c.dispose();
    }
    _nameFocus.dispose();
    for (final i in _items) {
      i.price.dispose();
    }
    super.dispose();
  }

  DateTime get _dueAt => widget.direct
      ? DateTime.now()
      : DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  int get _subtotal => _items.fold(0, (s, i) => s + i.qty * i.unitPrice);
  int get _discountValue => parseRupiahInput(_discount.text) ?? 0;
  int get _shippingValue =>
      _fulfillment == Fulfillment.delivery || widget.direct
      ? parseRupiahInput(_shipping.text) ?? 0
      : 0;
  int get _itemsRevenue => _subtotal - _discountValue;

  int _autoFee(List<SalesChannel> channels) {
    final channel = channels.where((c) => c.id == _channelId).firstOrNull;
    if (channel == null || _itemsRevenue <= 0) return 0;
    return channelFee(
      itemsTotal: _itemsRevenue,
      commissionPct: dec(channel.commissionPct),
      feePerOrder: channel.feePerOrder,
    );
  }

  int _feeValue(List<SalesChannel> channels) =>
      _feeEdited ? parseRupiahInput(_fee.text) ?? 0 : _autoFee(channels);

  OrderInput _input(List<SalesChannel> channels) => OrderInput(
    type: widget.direct ? OrderType.direct : OrderType.preOrder,
    dueAt: _dueAt,
    items: [
      for (final i in _items)
        OrderItemInput(
          productId: i.productId,
          qty: i.qty,
          unitPrice: i.unitPrice,
        ),
    ],
    customerName: _name.text.trim().isEmpty ? null : _name.text.trim(),
    customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    customerAddress: _fulfillment == Fulfillment.delivery
        ? _address.text.trim()
        : null,
    channelId: _channelId,
    fulfillment: _fulfillment,
    deliveryAddress: _fulfillment == Fulfillment.delivery
        ? _address.text.trim()
        : null,
    discount: _discountValue,
    shippingFee: _shippingValue,
    channelFee: _feeValue(channels),
    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    reminders: widget.direct
        ? const []
        : [
            for (final r in _reminders)
              if (r.enabled) r.input,
          ],
  );

  Future<void> _addItem(List<ProductView> products) async {
    final used = {for (final i in _items) i.productId};
    final picked = await showModalBottomSheet<ProductView>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: products.isEmpty
            ? const Center(child: Text('Belum ada menu. Buat menu dulu.'))
            : ListView(
                children: [
                  for (final p in products)
                    if (!used.contains(p.product.id))
                      ListTile(
                        title: Text(p.product.name),
                        subtitle: Text(
                          '${formatRupiah(p.product.sellingPrice)}/pcs · '
                          '${modeLabel(p.mode).toLowerCase()}'
                          '${p.isReadyStock ? ' · stok ${formatDecimal(p.stock)}' : ''}',
                        ),
                        onTap: () => Navigator.pop(context, p),
                      ),
                ],
              ),
      ),
    );
    if (picked == null) return;
    setState(
      () => _items.add(
        _ItemRow(picked.product.id, price: picked.product.sellingPrice),
      ),
    );
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _addCustomReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: _date.add(const Duration(days: 1)),
      helpText: 'Tanggal pengingat',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Jam pengingat',
    );
    if (time == null) return;
    setState(
      () => _reminders.add(
        _ReminderRow(
          ReminderInput.custom(
            DateTime(date.year, date.month, date.day, time.hour, time.minute),
          ),
        ),
      ),
    );
  }

  Future<void> _save(List<SalesChannel> channels) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    if (_items.isEmpty) return say('Tambahkan minimal satu item.');
    if (_discountValue > _subtotal) {
      return say('Diskon lebih besar dari subtotal.');
    }
    final input = _input(channels);
    final paid = parseRupiahInput(_paid.text) ?? 0;
    setState(() => _saving = true);
    final repo = ref.read(orderRepositoryProvider);
    try {
      final business = await ref.read(currentBusinessProvider.future);
      if (widget.direct) {
        await repo.recordDirectSale(business.id, input, method: _method);
        if (!mounted) return;
        context.pop();
        say('Penjualan ${formatRupiah(input.total)} dicatat.');
      } else if (widget.id == null) {
        final id = await repo.createOrder(business.id, input);
        if (paid > 0) {
          await repo.addPayment(
            id,
            amount: paid,
            method: _method,
            kind: paid >= input.total ? PaymentKind.settlement : PaymentKind.dp,
          );
        }
        if (!mounted) return;
        context.pushReplacement('/pesanan/$id');
        say('Pesanan disimpan.');
      } else {
        await repo.updateOrder(widget.id!, input);
        if (!mounted) return;
        context.pop();
        say('Pesanan diperbarui.');
      }
    } on InsufficientProductStockException catch (e) {
      if (mounted) setState(() => _saving = false);
      if (!mounted) return;
      final products = ref.read(productsProvider).value ?? const [];
      final short = products.where(
        (p) => e.shortages.containsKey(p.product.name),
      );
      await showStockShortDialog(
        context,
        e,
        short.isEmpty ? _items.first.productId : short.first.product.id,
      );
    } catch (error) {
      say('Gagal menyimpan: $error');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.direct
        ? 'Jual langsung'
        : widget.id == null
        ? 'Pesanan baru'
        : 'Ubah pesanan';
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final products = ref.watch(productsProvider).value ?? const [];
    final channels = (ref.watch(channelsProvider).value ?? const [])
        .where((c) => c.isActive || c.id == _channelId)
        .toList();
    final byId = {for (final p in products) p.product.id: p};
    if (!_feeEdited) _fee.text = formatRupiahDigits(_autoFee(channels));
    final fee = _feeValue(channels);
    final cogs = _items.fold(
      Decimal.zero,
      (s, i) =>
          s +
          (byId[i.productId]?.hppPerPcs ?? Decimal.zero) *
              Decimal.fromInt(i.qty),
    );
    final total = _itemsRevenue + _shippingValue;
    final profit = rupiah(_itemsRevenue - fee) - cogs;
    final paid = widget.direct ? total : parseRupiahInput(_paid.text) ?? 0;
    final incomplete = _items.any(
      (i) => byId[i.productId]?.status == HppStatus.incomplete,
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          SectionTitle(widget.direct ? 'Pembeli (opsional)' : 'Pelanggan'),
          const SizedBox(height: 8),
          _customerField(),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'No. WhatsApp (opsional)',
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Channel penjualan'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoicePill(
                label: 'Langsung',
                selected: _channelId == null,
                onSelected: () => setState(() {
                  _channelId = null;
                  _feeEdited = false;
                }),
              ),
              for (final c in channels)
                ChoicePill(
                  label: c.commissionPct > 0
                      ? '${c.name} · ${formatDecimal(dec(c.commissionPct))}%'
                      : c.name,
                  selected: _channelId == c.id,
                  onSelected: () => setState(() {
                    _channelId = c.id;
                    _feeEdited = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Potongan tiap channel diatur di Pengaturan dan bisa diubah per '
            'pesanan.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Item'),
          const SizedBox(height: 8),
          for (final row in _items) ...[
            _itemCard(row, byId[row.productId]),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => _addItem(products),
            icon: const Icon(Icons.add),
            label: const Text('Tambah item'),
          ),
          if (incomplete) ...[
            const SizedBox(height: 8),
            const InfoBox(
              'Ada menu dengan HPP belum lengkap; laba pesanan ini ditandai '
              'sampai harga bahannya diisi.',
            ),
          ],
          if (!widget.direct) ...[
            const SizedBox(height: 20),
            const SectionTitle('Jadwal'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(formatLongDate(_date)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    '${_time.hour.toString().padLeft(2, '0')}.'
                    '${_time.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final f in Fulfillment.values)
                  ChoicePill(
                    label: f == Fulfillment.pickup ? 'Ambil sendiri' : 'Antar',
                    selected: _fulfillment == f,
                    onSelected: () => setState(() => _fulfillment = f),
                  ),
              ],
            ),
            if (_fulfillment == Fulfillment.delivery) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Alamat antar'),
              ),
            ],
          ],
          const SizedBox(height: 20),
          const SectionTitle('Harga dan potongan'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: const [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Diskon',
                    prefixText: 'Rp ',
                  ),
                ),
              ),
              if (_fulfillment == Fulfillment.delivery || widget.direct) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _shipping,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: const [RupiahInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Ongkir',
                      prefixText: 'Rp ',
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_channelId != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _fee,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _feeEdited = true),
              inputFormatters: const [RupiahInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Potongan channel',
                prefixText: 'Rp ',
                helperText: _feeEdited
                    ? 'Diubah manual · otomatis ${formatRupiah(_autoFee(channels))}'
                    : 'Otomatis dari total item (tanpa ongkir)',
                suffixIcon: _feeEdited
                    ? IconButton(
                        tooltip: 'Kembalikan ke otomatis',
                        onPressed: () => setState(() => _feeEdited = false),
                        icon: const Icon(Icons.refresh),
                      )
                    : null,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SectionTitle(
            widget.direct ? 'Pembayaran' : 'Pembayaran dan pengingat',
          ),
          const SizedBox(height: 8),
          if (!widget.direct && widget.id == null) ...[
            TextField(
              controller: _paid,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'DP atau sudah dibayar (opsional)',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.direct || widget.id == null)
            Wrap(
              spacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoicePill(
                    label: methodLabel(m),
                    selected: _method == m,
                    onSelected: () => setState(() => _method = m),
                  ),
              ],
            ),
          if (!widget.direct) ...[
            const SizedBox(height: 8),
            for (final r in _reminders)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: r.enabled,
                onChanged: (v) => setState(() => r.enabled = v),
                title: Text('Ingatkan ${reminderLabel(r.input)}'),
                subtitle: Text(
                  '${formatShortDate(r.input.remindAt(_dueAt))} '
                  '${formatTime(r.input.remindAt(_dueAt))}',
                ),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: _addCustomReminder,
              icon: const Icon(Icons.add_alarm),
              label: const Text('Tambah pengingat'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
          ),
          const SizedBox(height: 20),
          const SectionTitle('Ringkasan'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SummaryRow('Subtotal', formatRupiah(_subtotal)),
                  if (_discountValue > 0)
                    SummaryRow('Diskon', formatRupiah(-_discountValue)),
                  if (_shippingValue > 0)
                    SummaryRow(
                      'Ongkir (bukan omzet)',
                      formatRupiah(_shippingValue),
                    ),
                  SummaryRow('Total tagihan', formatRupiah(total), bold: true),
                  const Divider(height: 16),
                  SummaryRow('Omzet item', formatRupiah(_itemsRevenue)),
                  if (fee > 0)
                    SummaryRow('Potongan channel', formatRupiah(-fee)),
                  SummaryRow(
                    'HPP${incomplete ? ' (belum lengkap)' : ''}',
                    formatRupiah(-toRupiah(cogs)),
                  ),
                  SummaryRow(
                    'Perkiraan laba',
                    formatRupiah(toRupiah(profit)),
                    bold: true,
                    color: profit >= Decimal.zero
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                  SummaryRow('Status bayar', switch (paymentStatusOf(
                    paid: paid,
                    total: total,
                  )) {
                    PaymentStatus.paid => 'Lunas',
                    PaymentStatus.partial =>
                      'DP, sisa ${formatRupiah(total - paid)}',
                    PaymentStatus.unpaid => 'Belum bayar',
                  }, color: paid <= 0 ? AppColors.danger : null),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _saving ? null : () => _save(channels),
          child: Text(
            _saving
                ? 'Menyimpan…'
                : widget.direct
                ? 'Simpan penjualan'
                : 'Simpan pesanan',
          ),
        ),
      ),
    );
  }

  Widget _customerField() {
    return RawAutocomplete<Customer>(
      textEditingController: _name,
      focusNode: _nameFocus,
      displayStringForOption: (c) => c.name,
      optionsBuilder: (value) async {
        final q = value.text.trim();
        if (q.length < 2) return const [];
        final business = await ref.read(currentBusinessProvider.future);
        return ref
            .read(orderRepositoryProvider)
            .searchCustomers(business.id, q);
      },
      onSelected: (c) => setState(() {
        _phone.text = c.phoneWa ?? _phone.text;
        if ((c.address ?? '').isNotEmpty) _address.text = c.address!;
      }),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nama'),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final c in options)
                  ListTile(
                    title: Text(c.name),
                    subtitle: c.phoneWa == null ? null : Text(c.phoneWa!),
                    onTap: () => onSelected(c),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(_ItemRow row, ProductView? view) {
    final short =
        view != null &&
        view.isReadyStock &&
        Decimal.fromInt(row.qty) > view.stock;
    final capacity = view?.capacity?.maxPcs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view?.product.name ?? '…',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (view != null)
                        Text(
                          '${modeLabel(view.mode).toLowerCase()} · HPP '
                          '${formatHpp(view)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus item',
                  onPressed: () => setState(() {
                    _items.remove(row);
                    row.price.dispose();
                  }),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Kurangi',
                  onPressed: row.qty > 1
                      ? () => setState(() => row.qty--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${row.qty}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Tambah',
                  onPressed: () => setState(() => row.qty++),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.price,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    onChanged: (_) => setState(() {}),
                    inputFormatters: const [RupiahInputFormatter()],
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: 'Rp ',
                      suffixText: '/pcs',
                    ),
                  ),
                ),
              ],
            ),
            if (short) ...[
              const SizedBox(height: 8),
              InfoBox(
                'Stok ${view.product.name.toLowerCase()} jadi '
                '${formatDecimal(view.stock)} pcs. Catat produksi sebelum '
                '${widget.direct ? 'menjual' : 'pesanan selesai'}'
                '${capacity == null ? '' : '; bahan cukup untuk $capacity pcs'}.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Baris label–nilai di kartu ringkasan.
class SummaryRow extends StatelessWidget {
  const SummaryRow(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 15 : 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Stok menu jadi kurang (FR-4.9): tawarkan mencatat produksi dulu.
Future<void> showStockShortDialog(
  BuildContext context,
  InsufficientProductStockException e,
  String productId,
) async {
  final produce = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Stok menu jadi kurang'),
      content: Text(
        [
          for (final MapEntry(key: name, value: qty) in e.shortages.entries)
            '$name kurang ${formatDecimal(qty)} pcs',
        ].join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Nanti'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Catat produksi'),
        ),
      ],
    ),
  );
  if (produce == true && context.mounted) {
    await context.push('/menu/$productId');
  }
}
