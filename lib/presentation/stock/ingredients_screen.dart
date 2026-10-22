import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/stock_repository.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../layout.dart';
import '../motion.dart';
import 'ingredient_detail_screen.dart';
import '../theme.dart';

enum _Filter { all, low, noPrice, archived }

/// Tab Bahan: nilai modal sisa bahan dan daftar bahan (mockup `Bahan`).
class IngredientsScreen extends ConsumerStatefulWidget {
  const IngredientsScreen({super.key});

  @override
  ConsumerState<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends ConsumerState<IngredientsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final ingredients = ref.watch(ingredientsProvider);
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Bahan'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/bahan/baru'),
            icon: const Icon(Icons.add),
            label: const Text('Bahan'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => context.push('/bahan/belanja'),
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: const Text('Belanja'),
            ),
          ),
        ],
      ),
      body: ingredients.when(
        loading: () => const SkeletonList(height: 72),
        error: (error, _) => Center(child: Text('Gagal memuat bahan: $error')),
        data: (list) => list.isEmpty ? const _EmptyState() : _content(list),
      ),
    );
    // Tablet mendatar: daftar dan detail berdampingan (FR-21.3).
    final first = ingredients.value?.where((v) => !v.isArchived).firstOrNull;
    return ListDetailLayout(
      list: scaffold,
      emptyText: 'Pilih bahan untuk melihat detailnya.',
      initialId: first?.ingredient.id,
      initialDetail: first == null
          ? null
          : (_) => IngredientDetailScreen(id: first.ingredient.id),
    );
  }

  Widget _content(List<IngredientView> list) {
    final sorted = [...list]
      ..sort((a, b) {
        if (a.avgUnitCost == null && b.avgUnitCost != null) return 1;
        if (b.avgUnitCost == null && a.avgUnitCost != null) return -1;
        return b.value.compareTo(a.value);
      });
    final shown = sorted.where(
      (v) => switch (_filter) {
        _Filter.archived => v.isArchived,
        _ when v.isArchived => false,
        _Filter.all => true,
        _Filter.low => v.isLow,
        _Filter.noPrice => v.avgUnitCost == null,
      },
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _ValueHero(list: sorted),
        const SizedBox(height: 12),
        const _ShoppingCard(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (filter, label) in [
              (_Filter.all, 'Semua'),
              (_Filter.low, 'Menipis'),
              (_Filter.noPrice, 'Belum ada harga'),
              if (sorted.any((v) => v.isArchived))
                (
                  _Filter.archived,
                  'Diarsipkan (${sorted.where((v) => v.isArchived).length})',
                ),
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
              'Tidak ada bahan untuk saringan ini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          )
        else
          _IngredientCards(
            children: [
              for (final (i, view) in shown.indexed)
                StaggeredEntrance(
                  key: ValueKey(view.ingredient.id),
                  index: i,
                  child: view.isArchived
                      ? ArchivedTile(
                          name: view.ingredient.name,
                          meta:
                              'Diarsipkan ${formatShortDate(view.ingredient.archivedAt!)} · '
                              'stok ${formatQty(view.stock, view.ingredient.unitLabel)}',
                          onTap: () =>
                              context.push('/bahan/${view.ingredient.id}'),
                          onRestore: () => runWithSnack(
                            context,
                            () => ref
                                .read(archiveRepositoryProvider)
                                .restoreIngredient(view.ingredient.id),
                            '${view.ingredient.name} dipulihkan.',
                          ),
                        )
                      : _IngredientRow(view),
                ),
            ],
          ),
        const SizedBox(height: 12),
        const Text(
          'Nilai = stok × harga rata-rata tertimbang. Harga rata-rata '
          'diperbarui setiap kali belanja dicatat.',
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

/// Baris bahan dalam satu kartu; di tablet tegak dibagi dua kartu
/// berdampingan (FR-21.5).
class _IngredientCards extends StatelessWidget {
  const _IngredientCards({required this.children});

  final List<Widget> children;

  Widget _card(List<Widget> rows) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1),
          r,
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560 || children.length < 2) {
          return _card(children);
        }
        final half = (children.length / 2).ceil();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _card(children.sublist(0, half))),
            const SizedBox(width: 12),
            Expanded(child: _card(children.sublist(half))),
          ],
        );
      },
    );
  }
}

/// Jalan masuk Daftar belanja di atas daftar bahan (FR-12.11).
class _ShoppingCard extends ConsumerWidget {
  const _ShoppingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(shoppingPlanProvider(3)).value;
    final list = ref.watch(activeShoppingListProvider).value;
    final todo = list?.todo ?? const [];
    final String detail;
    if (todo.isNotEmpty) {
      final total = todo.fold(0, (sum, l) => sum + (l.item.estimatedCost ?? 0));
      detail =
          '${todo.length} belum dibeli'
          '${total > 0 ? ' · ±${formatRupiah(total)}' : ''}';
    } else if (plan != null && plan.items.isNotEmpty) {
      detail =
          '${plan.items.length} bahan perlu dibeli'
          '${plan.total > 0 ? ' · ±${formatRupiah(plan.total)}' : ''}';
    } else {
      detail = 'Tidak ada yang perlu dibeli untuk 3 hari ke depan';
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/bahan/daftar-belanja'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daftar belanja',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => context.push('/bahan/daftar-belanja'),
                child: const Text('Buka'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueHero extends StatelessWidget {
  const _ValueHero({required this.list});

  final List<IngredientView> list;

  @override
  Widget build(BuildContext context) {
    final total = list.fold(0, (sum, v) => sum + v.value);
    final top = list.isEmpty ? null : list.first;
    final lowCount = list.where((v) => !v.isArchived && v.isLow).length;
    final noPriceCount = list
        .where((v) => !v.isArchived && v.avgUnitCost == null)
        .length;
    const muted = TextStyle(fontSize: 12, color: AppColors.onPrimaryMuted);
    const strong = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppColors.onPrimary,
    );
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
            'Nilai modal sisa bahan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onPrimaryMuted,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedRupiah(
            total,
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontSize: 34, color: AppColors.onPrimary),
          ),
          if (top != null && total > 0 && top.value > 0)
            Text(
              '${formatRupiah(top.value)} '
              '(${(top.value * 100 / total).round()}%) tertahan di '
              '${top.ingredient.name.toLowerCase()}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onPrimaryMuted,
              ),
            ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF8A5A40), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bahan menipis', style: muted),
                    Text('$lowCount', style: strong),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Belum ada harga', style: muted),
                    Text('$noPriceCount', style: strong),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow(this.view);

  final IngredientView view;

  @override
  Widget build(BuildContext context) {
    final ingredient = view.ingredient;
    final unit = ingredient.unitLabel;
    final avg = view.avgUnitCost;
    final details = [
      formatQty(view.stock, unit),
      if (avg == null)
        'harga belum diisi'
      else
        formatUnitPrice(avg, unit) +
            (ingredient.priceIsEstimate ? ' (perkiraan)' : ''),
      if (view.minStock > Decimal.zero)
        'minimum ${formatQty(view.minStock, unit)}',
    ].join(' · ');

    // Baris membesar menjadi Detail bahan (FR-11.8).
    return ContainerToDetail(
      radius: 0,
      bordered: false,
      detailId: ingredient.id,
      open: (_) => IngredientDetailScreen(id: ingredient.id),
      closed: (context, open) => InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          ingredient.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (view.isLow)
                          const StatusPill('Menipis', kind: StatusKind.danger),
                        if (avg == null)
                          const StatusPill(
                            'Belum ada harga',
                            kind: StatusKind.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                avg == null ? '—' : formatRupiah(view.value),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Belum ada bahan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tambahkan bahan yang sudah ada di rumah beserta stok awalnya, '
              'atau langsung catat belanja.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.push('/bahan/baru'),
              icon: const Icon(Icons.add),
              label: const Text('Tambah bahan'),
            ),
          ],
        ),
      ),
    );
  }
}
