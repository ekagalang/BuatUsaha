import '../../data/repositories/product_repository.dart';
import '../../domain/costing/costing.dart';
import '../../domain/enums.dart';
import '../common/format.dart';
import '../common/widgets.dart';

String modeLabel(StockDeductMode mode) => switch (mode) {
  StockDeductMode.onProduction => 'Ready stock',
  StockDeductMode.onComplete => 'Pre-order',
};

(String, StatusKind) hppStatusPill(HppStatus status) => switch (status) {
  HppStatus.complete => ('Lengkap', StatusKind.success),
  HppStatus.estimated => ('Perkiraan', StatusKind.neutral),
  HppStatus.incomplete => ('Belum lengkap', StatusKind.warning),
};

/// Tanda di kartu menu (FR-2.6, FR-2.8); `null` = tidak perlu perhatian.
(String, StatusKind)? menuBadge(ProductView view) {
  if (view.status == HppStatus.incomplete) {
    return ('HPP belum lengkap', StatusKind.warning);
  }
  return switch (view.warning) {
    PriceWarning.belowHpp => ('Di bawah HPP', StatusKind.danger),
    PriceWarning.belowTargetMargin => (
      'Margin di bawah target',
      StatusKind.warning,
    ),
    null =>
      view.status == HppStatus.estimated
          ? ('HPP perkiraan', StatusKind.neutral)
          : null,
  };
}

/// Rp4.835; HPP belum lengkap ditandai "+" karena angkanya masih kurang.
String formatHpp(ProductView view) {
  if (view.costing.lines.isEmpty) return '—';
  final text = formatRupiah(toRupiah(view.hppPerPcs));
  return view.status == HppStatus.incomplete ? '$text+' : text;
}

String formatMargin(ProductView view) {
  final margin = view.marginPct;
  return margin == null ? '—' : '${formatDecimal(margin, maxDecimals: 1)}%';
}

String limitingNames(ProductView view, CapacityResult capacity) => capacity
    .limitingIngredientIds
    .map(view.ingredientName)
    .whereType<String>()
    .map((name) => name.toLowerCase())
    .join(', ');

/// "Bisa jadi 30 pcs · pembatas: cokelat" (FR-3.1, FR-3.2).
String capacityLabel(ProductView view) {
  final capacity = view.capacity;
  if (capacity == null) return 'Resep belum punya bahan';
  final names = limitingNames(view, capacity);
  if (capacity.maxPcs <= 0) return 'Belum bisa dibuat · $names habis';
  return 'Bisa jadi ${capacity.maxPcs} pcs · pembatas: $names';
}
