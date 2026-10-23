import 'package:decimal/decimal.dart';

import '../enums.dart';

/// Satuan beli atau satuan resep dan faktornya ke satuan dasar bahan
/// (FR-1.2, FR-20.3).
class UnitOption {
  const UnitOption({
    required this.name,
    required this.factorToBase,
    this.isCustom = false,
    this.forRecipe = false,
  });

  final String name;
  final Decimal factorToBase;

  /// Konversi khusus bahan ini, mis. 1 pack mentega = 200 g.
  final bool isCustom;

  /// Satuan takaran resep (sdm, siung, …), tidak dipakai saat belanja.
  final bool forRecipe;
}

final _builtIn = <BaseUnit, List<(String, int)>>{
  BaseUnit.g: [('g', 1), ('ons', 100), ('kg', 1000)],
  BaseUnit.ml: [('ml', 1), ('liter', 1000)],
  BaseUnit.pcs: [('pcs', 1), ('lusin', 12), ('kodi', 20)],
};

/// Satuan dapur yang selalu ditawarkan di resep. Untuk bahan cair sudah ada
/// konversi bakunya; untuk bahan lain ditanya sekali per bahan.
const kitchenUnits = ['sdt', 'sdm', 'gelas'];
const _kitchenMl = [('sdt', 5), ('sdm', 15), ('gelas', 240)];

/// Nama satuan untuk dibandingkan: tanpa beda huruf besar/kecil dan spasi.
String normalizeUnitName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Satuan bawaan untuk [base] lalu konversi khusus bahan, tanpa nama ganda
/// (konversi khusus menang). [baseName] mengganti nama satuan dasar jumlah
/// (mis. butir). [recipe] menambah satuan dapur baku bahan cair.
List<UnitOption> unitOptionsFor(
  BaseUnit base, [
  List<UnitOption> custom = const [],
  String? baseName,
  bool recipe = false,
]) {
  final customNames = {for (final u in custom) normalizeUnitName(u.name)};
  final builtIn = [
    for (final (name, factor) in _builtIn[base]!)
      (factor == 1 && baseName != null ? baseName : name, factor),
    if (recipe && base == BaseUnit.ml) ..._kitchenMl,
  ];
  return [
    for (final (name, factor) in builtIn)
      if (factor == 1 || !customNames.contains(normalizeUnitName(name)))
        UnitOption(
          name: name,
          factorToBase: Decimal.fromInt(factor),
          forRecipe: kitchenUnits.contains(name),
        ),
    for (final u in custom)
      if (normalizeUnitName(u.name) != normalizeUnitName(baseName ?? base.code))
        u,
  ];
}

/// Nama satuan bawaan untuk [base] (kg, lusin, …), untuk disembunyikan.
List<(String, int)> builtInUnits(BaseUnit base) => [
  for (final (name, factor) in _builtIn[base]!)
    if (factor != 1) (name, factor),
];

/// Stok di bawah ambang minimum (FR-1.6). Ambang 0 = tidak dipantau.
bool isLowStock({required Decimal stock, required Decimal minStock}) =>
    minStock > Decimal.zero && stock < minStock;
