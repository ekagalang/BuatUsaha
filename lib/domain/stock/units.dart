import 'package:decimal/decimal.dart';

import '../enums.dart';

/// Satuan beli dan faktornya ke satuan dasar bahan (FR-1.2).
class UnitOption {
  const UnitOption({
    required this.name,
    required this.factorToBase,
    this.isCustom = false,
  });

  final String name;
  final Decimal factorToBase;

  /// Konversi khusus bahan ini, mis. 1 pack mentega = 200 g.
  final bool isCustom;
}

final _builtIn = <BaseUnit, List<(String, int)>>{
  BaseUnit.g: [('g', 1), ('ons', 100), ('kg', 1000)],
  BaseUnit.ml: [('ml', 1), ('liter', 1000)],
  BaseUnit.pcs: [('pcs', 1), ('lusin', 12), ('kodi', 20)],
};

/// Satuan bawaan untuk [base] lalu konversi khusus bahan, tanpa nama ganda
/// (konversi khusus menang).
List<UnitOption> unitOptionsFor(
  BaseUnit base, [
  List<UnitOption> custom = const [],
]) {
  final customNames = {for (final u in custom) u.name.toLowerCase()};
  return [
    for (final (name, factor) in _builtIn[base]!)
      if (!customNames.contains(name))
        UnitOption(name: name, factorToBase: Decimal.fromInt(factor)),
    ...custom,
  ];
}

/// Stok di bawah ambang minimum (FR-1.6). Ambang 0 = tidak dipantau.
bool isLowStock({required Decimal stock, required Decimal minStock}) =>
    minStock > Decimal.zero && stock < minStock;
