import 'package:decimal/decimal.dart';

import '../enums.dart';
import 'money.dart';

/// Satu bahan dalam resep: takaran per 1 resep dan harga rata-rata terkini.
class RecipeLine {
  const RecipeLine({
    required this.ingredientId,
    required this.qtyPerBatch,
    required this.unitCost,
    this.isEstimate = false,
  });

  final String ingredientId;

  /// Dalam satuan dasar bahan.
  final Decimal qtyPerBatch;

  /// Rp per satuan dasar; `null` = bahan belum punya harga.
  final Decimal? unitCost;

  /// Harga masih perkiraan (FR-1.7), belum dari belanja.
  final bool isEstimate;

  /// `null` jika bahan belum punya harga.
  Decimal? get cost {
    final price = unitCost;
    return price == null ? null : qtyPerBatch * price;
  }
}

/// Biaya tanpa stok, per resep atau per pcs.
class OtherCost {
  const OtherCost({
    required this.name,
    required this.amount,
    required this.basis,
  });

  final String name;
  final int amount;
  final CostBasis basis;
}

class HppBreakdown {
  const HppBreakdown({
    required this.materialCostPerBatch,
    required this.otherCostPerBatch,
    required this.otherCostPerPcs,
    required this.yieldQty,
    required this.hppPerPcs,
    required this.status,
    required this.missingPriceIngredientIds,
  });

  /// Hanya dari bahan yang sudah punya harga.
  final Decimal materialCostPerBatch;
  final Decimal otherCostPerBatch;
  final Decimal otherCostPerPcs;
  final Decimal yieldQty;

  /// Jika [status] = [HppStatus.incomplete], angka ini lebih rendah dari
  /// kenyataan; UI tidak menampilkan saran harga (FR-2.8).
  final Decimal hppPerPcs;
  final HppStatus status;
  final List<String> missingPriceIngredientIds;

  Decimal get totalCostPerBatch => materialCostPerBatch + otherCostPerBatch;
}

/// Upah pemilik per resep = jam kerja × upah per jam, dibulatkan ke Rupiah.
int laborCost({required Decimal hours, required int hourlyWage}) =>
    toRupiah(hours * rupiah(hourlyWage));

/// HPP per pcs = (Σ takaran × harga + biaya lain per resep) / hasil + biaya lain per pcs.
HppBreakdown calculateHpp({
  required List<RecipeLine> lines,
  List<OtherCost> otherCosts = const [],
  required Decimal yieldQty,
}) {
  if (yieldQty <= Decimal.zero) {
    throw ArgumentError.value(yieldQty, 'yieldQty', 'harus > 0');
  }
  var material = Decimal.zero;
  final missing = <String>[];
  var estimated = false;
  for (final line in lines) {
    final cost = line.cost;
    if (cost == null) {
      missing.add(line.ingredientId);
    } else {
      material += cost;
      estimated = estimated || line.isEstimate;
    }
  }
  var otherPerBatch = Decimal.zero;
  var otherPerPcs = Decimal.zero;
  for (final cost in otherCosts) {
    switch (cost.basis) {
      case CostBasis.perBatch:
        otherPerBatch += rupiah(cost.amount);
      case CostBasis.perPcs:
        otherPerPcs += rupiah(cost.amount);
    }
  }
  final status = missing.isNotEmpty
      ? HppStatus.incomplete
      : estimated
      ? HppStatus.estimated
      : HppStatus.complete;
  return HppBreakdown(
    materialCostPerBatch: material,
    otherCostPerBatch: otherPerBatch,
    otherCostPerPcs: otherPerPcs,
    yieldQty: yieldQty,
    hppPerPcs: divide(material + otherPerBatch, yieldQty) + otherPerPcs,
    status: status,
    missingPriceIngredientIds: missing,
  );
}
