import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/cash_repository.dart';
import '../common/widgets.dart';
import '../theme.dart';

/// Baris "Dibayar dari" di form Belanja dan Pengeluaran (FR-15.2). [value]
/// `null` = Tunai.
class CashAccountPicker extends ConsumerWidget {
  const CashAccountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Dibayar dari',
    this.required = false,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String label;

  /// Tanpa pilihan bawaan: tidak ada yang terpilih sampai diketuk.
  final bool required;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(cashAccountsProvider).value ?? const [];
    if (accounts.isEmpty) return const SizedBox.shrink();
    final fallback = required
        ? null
        : defaultCashAccountId(accounts.first.businessId);
    final selected = accounts.any((a) => a.id == value) ? value : fallback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in accounts)
              if (a.isActive || a.id == selected)
                ChoicePill(
                  label: a.name,
                  selected: a.id == selected,
                  onSelected: () => onChanged(a.id),
                ),
          ],
        ),
      ],
    );
  }
}
