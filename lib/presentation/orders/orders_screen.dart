import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/order_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'order_labels.dart';

enum _View { calendar, list }

enum _StatusFilter { open, all, done }

/// Tab Pesanan: kalender bulanan + daftar per tanggal, atau daftar Hari ini /
/// Besok / 7 hari (FR-5.4, mockup `Pesanan`).
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  var _view = _View.calendar;
  var _filter = _StatusFilter.open;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _day = _today;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _matches(OrderView v) => switch (_filter) {
    _StatusFilter.open => v.isOpen,
    _StatusFilter.all => true,
    _StatusFilter.done => !v.isOpen,
  };

  @override
  Widget build(BuildContext context) {
    // Satu langganan untuk bulan yang tampil dan 7 hari ke depan.
    final from = _month.isBefore(_today) ? _month : _today;
    final monthEnd = DateTime(_month.year, _month.month + 1);
    final weekEnd = _today.add(const Duration(days: 8));
    final to = monthEnd.isAfter(weekEnd) ? monthEnd : weekEnd;
    final orders = ref.watch(ordersInRangeProvider((from, to)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan'),
        actions: [
          IconButton(
            tooltip: 'Jual langsung',
            onPressed: () => context.push('/pesanan/jual'),
            icon: const Icon(Icons.sell_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => context.push(
                '/pesanan/baru?tanggal=${_day.toIso8601String()}',
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Baru'),
            ),
          ),
        ],
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat pesanan: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Segmented(
              labels: const ['Kalender', 'Daftar'],
              selected: _view.index,
              onSelected: (i) => setState(() => _view = _View.values[i]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (f, label) in const [
                  (_StatusFilter.open, 'Belum selesai'),
                  (_StatusFilter.all, 'Semua'),
                  (_StatusFilter.done, 'Selesai/batal'),
                ])
                  ChoicePill(
                    label: label,
                    selected: _filter == f,
                    onSelected: () => setState(() => _filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_view == _View.calendar)
              ..._calendar(list)
            else
              ..._agenda(list),
          ],
        ),
      ),
    );
  }

  List<Widget> _calendar(List<OrderView> list) {
    final now = DateTime.now();
    final byDay = <DateTime, List<OrderView>>{};
    for (final v in list) {
      final d = v.order.dueAt.toLocal();
      (byDay[DateTime(d.year, d.month, d.day)] ??= []).add(v);
    }
    final dayOrders = (byDay[_day] ?? const <OrderView>[])
        .where(_matches)
        .toList();
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
          child: _MonthGrid(
            month: _month,
            selected: _day,
            today: _today,
            counts: {
              for (final MapEntry(key: day, value: orders) in byDay.entries)
                day: (
                  orders
                      .where((o) => o.order.status != OrderStatus.cancelled)
                      .length,
                  orders.any((o) => o.isLate(now)),
                ),
            },
            onMonth: (m) => setState(() => _month = m),
            onDay: (d) => setState(() => _day = d),
          ),
        ),
      ),
      const SizedBox(height: 16),
      SectionTitle(
        '${formatLongDate(_day).split(' ').take(3).join(' ')}'
        '${dayOrders.isEmpty ? '' : ' · ${dayOrders.length} pesanan'}',
      ),
      const SizedBox(height: 8),
      if (dayOrders.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Belum ada pesanan di tanggal ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        )
      else ...[
        for (final v in dayOrders) ...[OrderCard(v), const SizedBox(height: 8)],
        _NeedsCard(day: _day),
      ],
    ];
  }

  List<Widget> _agenda(List<OrderView> list) {
    final now = DateTime.now();
    final tomorrow = _today.add(const Duration(days: 1));
    final after = _today.add(const Duration(days: 2));
    final weekEnd = _today.add(const Duration(days: 8));
    final shown = list.where(_matches).toList();
    DateTime dayOf(OrderView v) {
      final d = v.order.dueAt.toLocal();
      return DateTime(d.year, d.month, d.day);
    }

    final groups = [
      ('Terlambat', shown.where((v) => v.isLate(now)).toList()),
      (
        'Hari ini',
        shown.where((v) => dayOf(v) == _today && !v.isLate(now)).toList(),
      ),
      ('Besok', shown.where((v) => dayOf(v) == tomorrow).toList()),
      (
        '7 hari ke depan',
        shown
            .where(
              (v) => !dayOf(v).isBefore(after) && dayOf(v).isBefore(weekEnd),
            )
            .toList(),
      ),
    ];
    if (groups.every((g) => g.$2.isEmpty)) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Text(
            'Tidak ada pesanan dalam 7 hari ke depan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      ];
    }
    return [
      for (final (title, orders) in groups)
        if (orders.isNotEmpty) ...[
          SectionTitle('$title · ${orders.length}'),
          const SizedBox(height: 8),
          for (final v in orders) ...[
            OrderCard(v, showDate: title != 'Hari ini'),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
    ];
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.counts,
    required this.onMonth,
    required this.onDay,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;

  /// Tanggal → (jumlah pesanan, ada yang terlambat).
  final Map<DateTime, (int, bool)> counts;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onDay;

  static const _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month).weekday - 1;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _cell(DateTime(month.year, month.month, d)),
    ];
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Bulan sebelumnya',
              onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${_months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Bulan berikutnya',
              onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in const [
              'Sen',
              'Sel',
              'Rab',
              'Kam',
              'Jum',
              'Sab',
              'Min',
            ])
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: cells,
        ),
      ],
    );
  }

  Widget _cell(DateTime day) {
    final isSelected = day == selected;
    final isToday = day == today;
    final (count, late) = counts[day] ?? (0, false);
    return Semantics(
      button: true,
      label:
          '${day.day} ${_months[day.month - 1]}, '
          '${count > 0 ? '$count pesanan' : 'tidak ada pesanan'}'
          '${isToday ? ', hari ini' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onDay(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : null,
            borderRadius: BorderRadius.circular(12),
            border: isToday && !isSelected
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: isSelected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected ? AppColors.onPrimary : AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: count == 0
                      ? Colors.transparent
                      : late
                      ? AppColors.dangerStrong
                      : isSelected
                      ? AppColors.primaryContainer
                      : AppColors.accentWarm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu pesanan di daftar (mockup `Pesanan`).
class OrderCard extends StatelessWidget {
  const OrderCard(this.view, {super.key, this.showDate = false});

  final OrderView view;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final order = view.order;
    final (status, kind) = orderStatusPill(view, DateTime.now());
    final when = showDate
        ? '${formatShortDate(order.dueAt)} ${formatTime(order.dueAt)}'
        : formatTime(order.dueAt);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/pesanan/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      when,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      fulfillmentLabel(order.fulfillment),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(itemsSummary(view)),
                    Text(
                      '${channelName(view)} · ${paymentLabel(view)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: order.paymentStatus == PaymentStatus.unpaid
                            ? AppColors.danger
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(status, kind: kind),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kebutuhan produksi untuk tanggal terpilih (FR-5.5).
class _NeedsCard extends ConsumerWidget {
  const _NeedsCard({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needs = ref.watch(productionNeedsProvider(day)).value;
    if (needs == null || needs.products.isEmpty) {
      return const SizedBox.shrink();
    }
    final toMake = needs.products.where((p) => p.toMake > Decimal.zero);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Kebutuhan produksi'),
            const SizedBox(height: 8),
            for (final p in needs.products)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(p.product.name)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        p.toMake > Decimal.zero
                            ? 'pesan ${p.orderedQty} · buat ${formatDecimal(p.toMake)}'
                            : 'pesan ${p.orderedQty} · stok cukup',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (toMake.isEmpty)
              const InfoBox(
                'Stok menu jadi cukup untuk semua pesanan tanggal ini.',
                kind: StatusKind.success,
              )
            else if (needs.shortages.isEmpty)
              const InfoBox(
                'Stok bahan cukup untuk produksi tanggal ini.',
                kind: StatusKind.success,
              )
            else ...[
              InfoBox(
                'Bahan kurang: ${needs.shortages.map((s) => '${s.ingredient.name} ${formatQty(s.missingQty, s.ingredient.baseUnit.code)}').join(', ')}. '
                'Perkiraan belanja ${formatRupiah(toRupiah(needs.shortages.fold(Decimal.zero, (sum, s) => sum + (s.estimatedCost ?? Decimal.zero))))}.',
                kind: StatusKind.danger,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
