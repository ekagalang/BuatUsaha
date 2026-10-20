import 'package:decimal/decimal.dart';

import 'hpp_calculator.dart';
import 'money.dart';

class CapacityResult {
  const CapacityResult({
    required this.maxPcs,
    required this.maxBatches,
    required this.limitingIngredientIds,
  });

  final int maxPcs;
  final Decimal maxBatches;

  /// Bahan pembatas: bahan dengan stok / takaran terkecil.
  final List<String> limitingIngredientIds;
}

class Shortage {
  const Shortage({
    required this.ingredientId,
    required this.requiredQty,
    required this.availableQty,
    required this.missingQty,
    required this.estimatedCost,
  });

  final String ingredientId;
  final Decimal requiredQty;
  final Decimal availableQty;
  final Decimal missingQty;

  /// `null` jika bahan belum punya harga.
  final Decimal? estimatedCost;
}

/// Bisa jadi berapa pcs dari stok saat ini.
///
/// [stock] = saldo per `ingredientId` dalam satuan dasar; bahan yang tidak ada
/// dianggap 0. Jika [wholeBatchesOnly], resep tidak boleh dipecah.
CapacityResult calculateCapacity({
  required List<RecipeLine> lines,
  required Map<String, Decimal> stock,
  required Decimal yieldQty,
  bool wholeBatchesOnly = false,
}) {
  final used = lines.where((line) => line.qtyPerBatch > Decimal.zero).toList();
  if (used.isEmpty) {
    throw ArgumentError.value(lines, 'lines', 'resep belum punya bahan');
  }
  if (yieldQty <= Decimal.zero) {
    throw ArgumentError.value(yieldQty, 'yieldQty', 'harus > 0');
  }

  Decimal? minBatches;
  var limiting = <String>[];
  for (final line in used) {
    final available = _available(stock, line.ingredientId);
    final batches = divide(available, line.qtyPerBatch);
    if (minBatches == null || batches < minBatches) {
      minBatches = batches;
      limiting = [line.ingredientId];
    } else if (batches == minBatches) {
      limiting.add(line.ingredientId);
    }
  }

  final batches = wholeBatchesOnly ? minBatches!.floor() : minBatches!;
  return CapacityResult(
    maxPcs: (batches * yieldQty).floor().toBigInt().toInt(),
    maxBatches: batches,
    limitingIngredientIds: limiting,
  );
}

/// Bahan yang kurang untuk membuat [targetPcs] beserta perkiraan biaya belanjanya.
List<Shortage> calculateShortages({
  required List<RecipeLine> lines,
  required Map<String, Decimal> stock,
  required Decimal yieldQty,
  required int targetPcs,
}) {
  if (yieldQty <= Decimal.zero) {
    throw ArgumentError.value(yieldQty, 'yieldQty', 'harus > 0');
  }
  final batches = divide(Decimal.fromInt(targetPcs), yieldQty);
  final shortages = <Shortage>[];
  for (final line in lines) {
    final requiredQty = batches * line.qtyPerBatch;
    final available = _available(stock, line.ingredientId);
    final missingQty = requiredQty - available;
    final unitCost = line.unitCost;
    if (missingQty > Decimal.zero) {
      shortages.add(
        Shortage(
          ingredientId: line.ingredientId,
          requiredQty: requiredQty,
          availableQty: available,
          missingQty: missingQty,
          estimatedCost: unitCost == null ? null : missingQty * unitCost,
        ),
      );
    }
  }
  return shortages;
}

/// Bahan tanpa harga tidak ikut dihitung.
int estimateShoppingCost(Iterable<Shortage> shortages) => toRupiah(
  shortages.fold(
    Decimal.zero,
    (sum, s) => sum + (s.estimatedCost ?? Decimal.zero),
  ),
);

/// Stok negatif diperlakukan sebagai 0.
Decimal _available(Map<String, Decimal> stock, String ingredientId) {
  final qty = stock[ingredientId] ?? Decimal.zero;
  return qty < Decimal.zero ? Decimal.zero : qty;
}
