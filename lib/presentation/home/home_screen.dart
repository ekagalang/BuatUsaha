import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/stock_repository.dart' show IngredientUnitLabel;
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../orders/orders_screen.dart' show OrderCard;
import '../reports/expenses_screen.dart';
import '../layout.dart';
import '../motion.dart';
import '../theme.dart';
import '../update/update_widgets.dart';

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Beranda: status untung/rugi hari ini, catat cepat, pesanan hari ini dan
/// besok, nilai modal, dan hal yang perlu perhatian (PRD 7, mockup `Main`).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider).value;
    if (business != null && business.onboardedAt == null) {
      // Cek ulang dari database: nilai stream bisa tertinggal sesaat setelah
      // onboarding selesai.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final fresh = await ref
            .read(businessRepositoryProvider)
            .watch(business.id)
            .first;
        if (fresh.onboardedAt == null && context.mounted) {
          context.go('/onboarding');
        }
      });
    }
    final today = _today();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beranda'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            onPressed: () => context.push('/pengaturan'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            formatLongDate(today),
            style: const TextStyle(color: AppColors.textMuted),
          ),
          if (business != null && business.name != 'Usaha saya')
            Text(
              business.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          // Versi baru tersedia (FR-11.4), di atas status hari ini.
          const UpdateCard(),
          const SizedBox(height: 12),
          // Tablet: status di kiri, catat cepat dan pesanan di kanan
          // (FR-21.4); di HP bertumpuk seperti biasa.
          TwoColumns(
            left: [
              _TodayHero(day: today),
              const SizedBox(height: 20),
              _Values(day: today),
              const SizedBox(height: 20),
              const _Attention(),
            ],
            right: [
              const SectionTitle('Catat cepat'),
              const SizedBox(height: 8),
              const _QuickActions(),
              const SizedBox(height: 20),
              _OrdersToday(day: today),
              const SizedBox(height: 20),
            ],
            narrow: [
              _TodayHero(day: today),
              const SizedBox(height: 20),
              const SectionTitle('Catat cepat'),
              const SizedBox(height: 8),
              const _QuickActions(),
              const SizedBox(height: 20),
              _OrdersToday(day: today),
              const SizedBox(height: 20),
              _Values(day: today),
              const SizedBox(height: 20),
              const _Attention(),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayHero extends ConsumerWidget {
  const _TodayHero({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(dayReportProvider(day)).value;
    final s = report?.summary;
    final net = s?.netProfit ?? 0;
    final (label, kind) = net > 0
        ? ('Untung', StatusKind.success)
        : net < 0
        ? ('Rugi', StatusKind.danger)
        : ('Impas', StatusKind.neutral);
    const muted = TextStyle(fontSize: 12, color: AppColors.onPrimaryMuted);
    const strong = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary,
    );
    Widget stat(String l, int v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: muted),
          AnimatedRupiah(v, style: strong),
        ],
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.go('/laporan'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    report?.closed ?? false
                        ? 'Hari ini, setelah Tutup hari'
                        : 'Hari ini',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onPrimaryMuted,
                    ),
                  ),
                ),
                StatusPill(label, kind: kind),
              ],
            ),
            AnimatedRupiah(
              net,
              style: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(fontSize: 34, color: AppColors.onPrimary),
            ),
            Text(
              'Laba bersih, sudah dikurangi pengeluaran '
              '${formatRupiah(s?.expenses ?? 0)}',
              style: muted,
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF8A5A40), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                stat('Omzet', s?.revenue ?? 0),
                stat('Laba menu', s?.menuProfit ?? 0),
                stat('Rugi sisa', s?.wasteLoss ?? 0),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Lihat per menu ›',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      (
        'Pesanan baru',
        Icons.receipt_outlined,
        () => context.push('/pesanan/baru'),
      ),
      ('Penjualan', Icons.sell_outlined, () => context.push('/pesanan/jual')),
      (
        'Belanja',
        Icons.shopping_cart_outlined,
        () => context.push('/bahan/belanja'),
      ),
      (
        'Produksi',
        Icons.local_fire_department_outlined,
        () => _pickMenu(context, ref),
      ),
      (
        'Pengeluaran',
        Icons.account_balance_wallet_outlined,
        () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const ExpenseSheet(),
        ),
      ),
      (
        'Tutup hari',
        Icons.nights_stay_outlined,
        () => context.push('/tutup-hari'),
      ),
    ];
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Tinggi tetap (ikut besar huruf), tidak bergantung lebar kolom.
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 60 + MediaQuery.textScalerOf(context).scale(36),
      ),
      children: [
        for (final (label, icon, onTap) in actions)
          Pressable(
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: AppColors.primary),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Catat produksi lewat detail menu ready stock.
  Future<void> _pickMenu(BuildContext context, WidgetRef ref) async {
    final menus = (ref.read(productsProvider).value ?? const <ProductView>[])
        .where(
          (p) => !p.isArchived && p.isReadyStock && p.costing.lines.isNotEmpty,
        )
        .toList();
    if (menus.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada menu ready stock dengan resep.'),
        ),
      );
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          for (final m in menus)
            ListTile(
              title: Text(m.product.name),
              subtitle: Text(
                'stok ${formatDecimal(m.stock)} pcs · '
                '${m.capacity == null ? '' : 'bisa jadi ${m.capacity!.maxPcs} pcs'}',
              ),
              onTap: () => Navigator.pop(context, m.product.id),
            ),
        ],
      ),
    );
    if (id != null && context.mounted) await context.push('/menu/$id');
  }
}

class _OrdersToday extends ConsumerWidget {
  const _OrdersToday({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tomorrow = day.add(const Duration(days: 1));
    final orders =
        ref
            .watch(
              ordersInRangeProvider((day, day.add(const Duration(days: 2)))),
            )
            .value ??
        const <OrderView>[];
    final open = orders.where((o) => o.isOpen).toList();
    DateTime dayOf(OrderView v) {
      final d = v.order.dueAt.toLocal();
      return DateTime(d.year, d.month, d.day);
    }

    final todays = open.where((o) => dayOf(o) == day).toList();
    final tomorrows = open.where((o) => dayOf(o) == tomorrow).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Pesanan hari ini (${todays.length})',
          trailing: TextButton(
            onPressed: () => context.go('/pesanan'),
            child: const Text('Lihat semua'),
          ),
        ),
        if (todays.isEmpty)
          const Text(
            'Tidak ada pesanan yang belum selesai hari ini.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        for (final o in todays) ...[OrderCard(o), const SizedBox(height: 8)],
        if (tomorrows.isNotEmpty) ...[
          const SizedBox(height: 8),
          SectionTitle('Besok (${tomorrows.length})'),
          const SizedBox(height: 8),
          for (final o in tomorrows) ...[
            OrderCard(o),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _Values extends ConsumerWidget {
  const _Values({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = (
      DateTime(day.year, day.month),
      DateTime(day.year, day.month + 1),
    );
    final period = ref.watch(periodReportProvider(month)).value;
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    final products = ref.watch(productsProvider).value ?? const [];
    final ingredientValue = ingredients.fold(0, (s, v) => s + v.value);
    final productValue = products
        .where((p) => p.isReadyStock)
        .fold(0, (s, p) => s + p.stockValue);
    Widget tile(String label, int value, VoidCallback onTap) => Expanded(
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupiah(value),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: value < 0 ? AppColors.danger : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        tile(
          'Laba bulan ini',
          period?.netProfit ?? 0,
          () => context.go('/laporan'),
        ),
        tile('Modal bahan', ingredientValue, () => context.go('/bahan')),
        tile('Stok menu jadi', productValue, () => context.go('/menu')),
      ],
    );
  }
}

const _shoppingPath = '/bahan/daftar-belanja';

class _Attention extends ConsumerWidget {
  const _Attention();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredients = ref.watch(ingredientsProvider).value ?? const [];
    final products = ref.watch(productsProvider).value ?? const [];
    final today = _today();
    final orders =
        ref
            .watch(
              ordersInRangeProvider((
                today.subtract(const Duration(days: 30)),
                today.add(const Duration(days: 1)),
              )),
            )
            .value ??
        const <OrderView>[];
    final now = DateTime.now();
    final corrections = ref.watch(costCorrectionsProvider).value ?? const [];
    // Daftar belanja untuk pesanan 3 hari ke depan (FR-12.11).
    final shopping = ref.watch(shoppingPlanProvider(3)).value;
    final items = <(String, String, String)>[
      if (shopping != null && shopping.items.isNotEmpty)
        (
          'Perlu dibeli · ${shopping.items.length} bahan',
          '${shopping.total > 0 ? '±${formatRupiah(shopping.total)} ' : ''}'
              'untuk pesanan 3 hari ke depan',
          _shoppingPath,
        ),
      if (corrections.isNotEmpty)
        (
          '${corrections.length} pesanan lama memakai HPP sebelum koreksi',
          'Harga bahan dikoreksi; tinjau dan hitung ulang labanya',
          '/pesanan/koreksi-hpp',
        ),
      for (final i in ingredients.where((i) => i.isLow))
        (
          '${i.ingredient.name} menipis',
          'Sisa ${formatQty(i.stock, i.ingredient.unitLabel)}, batas '
              'minimum ${formatQty(i.minStock, i.ingredient.unitLabel)}',
          '/bahan/${i.ingredient.id}',
        ),
      for (final p in products.where(
        (p) => p.status == HppStatus.incomplete && p.costing.lines.isNotEmpty,
      ))
        (
          '${p.product.name}: HPP belum lengkap',
          p.costing.wageMissing
              ? 'Upah per jam pemilik belum diisi'
              : '${p.hpp.missingPriceIngredientIds.map(p.ingredientName).whereType<String>().join(', ')} belum punya harga',
          '/menu/${p.product.id}',
        ),
      for (final o in orders.where((o) => o.isLate(now)))
        (
          'Terlambat: ${o.title}',
          '${o.order.orderNo} · jadwal ${formatShortDate(o.order.dueAt)} '
              '${formatTime(o.order.dueAt)}',
          '/pesanan/${o.order.id}',
        ),
      for (final o in orders.where(
        (o) =>
            o.order.status == OrderStatus.completed &&
            o.order.voidedAt == null &&
            o.order.paymentStatus != PaymentStatus.paid,
      ))
        (
          '${o.title} belum lunas',
          'Sisa ${formatRupiah(o.remaining)} · ${o.order.orderNo}',
          '/pesanan/${o.order.id}',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Perlu perhatian'),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, (title, detail, path)) in items.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: path == _shoppingPath
                      ? const Icon(
                          Icons.shopping_cart_outlined,
                          color: AppColors.primary,
                        )
                      : const Icon(
                          Icons.error_outline,
                          color: AppColors.warning,
                        ),
                  title: Text(title),
                  subtitle: Text(detail),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(path),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
