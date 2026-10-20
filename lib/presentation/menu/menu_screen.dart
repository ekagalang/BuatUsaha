import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';
import 'menu_labels.dart';

enum _Filter { all, ready, preOrder, attention }

/// Tab Menu: daftar menu beserta HPP, harga, margin, dan kapasitas (mockup
/// `Menu`).
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => context.push('/menu/baru'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Menu baru'),
            ),
          ),
        ],
      ),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Gagal memuat menu: $error')),
        data: (list) => list.isEmpty ? const _EmptyState() : _content(list),
      ),
    );
  }

  Widget _content(List<ProductView> list) {
    final shown = list.where(
      (v) => switch (_filter) {
        _Filter.all => true,
        _Filter.ready => v.isReadyStock,
        _Filter.preOrder => !v.isReadyStock,
        _Filter.attention => menuBadge(v) != null,
      },
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (filter, label) in const [
              (_Filter.all, 'Semua'),
              (_Filter.ready, 'Ready stock'),
              (_Filter.preOrder, 'Pre-order'),
              (_Filter.attention, 'Perlu perhatian'),
            ])
              ChoicePill(
                label: label,
                selected: _filter == filter,
                onSelected: () => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Tidak ada menu untuk saringan ini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          )
        else
          for (final view in shown) ...[
            _MenuCard(view),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 4),
        const Text(
          'Kapasitas dihitung per menu. Bahan dipakai bersama, jadi kapasitas '
          'antar menu tidak bisa dijumlahkan.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard(this.view);

  final ProductView view;

  @override
  Widget build(BuildContext context) {
    final product = view.product;
    final badge = menuBadge(view);
    final stock = view.isReadyStock
        ? 'stok ${formatDecimal(view.stock)} pcs'
        : 'tanpa stok';
    final capacity = view.capacity;
    final cantMake = capacity == null || capacity.maxPcs <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/menu/${product.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${modeLabel(view.mode)} · $stock',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    StatusPill(badge.$1, kind: badge.$2),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat('HPP/pcs', formatHpp(view)),
                  _Stat('Harga jual', formatRupiah(product.sellingPrice)),
                  _Stat(
                    'Margin',
                    formatMargin(view),
                    color: view.warning == null ? null : AppColors.danger,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                capacityLabel(view),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cantMake && view.status != HppStatus.complete
                      ? AppColors.warning
                      : cantMake
                      ? AppColors.textMuted
                      : AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.bakery_dining_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada menu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Buat menu dan isi resepnya. HPP, saran harga, dan "bisa jadi '
              'berapa pcs" dihitung otomatis dari harga dan stok bahan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/menu/baru'),
              icon: const Icon(Icons.add),
              label: const Text('Menu baru'),
            ),
          ],
        ),
      ),
    );
  }
}
