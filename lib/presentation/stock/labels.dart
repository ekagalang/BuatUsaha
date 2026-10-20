import '../../domain/enums.dart';

String categoryLabel(IngredientCategory category) => switch (category) {
  IngredientCategory.raw => 'Bahan baku',
  IngredientCategory.packaging => 'Kemasan',
  IngredientCategory.other => 'Lainnya',
};

String movementLabel(MovementType type, {required bool zeroQty}) =>
    switch (type) {
      MovementType.opening => zeroQty ? 'Harga perkiraan' : 'Stok awal',
      MovementType.purchase => 'Belanja',
      MovementType.production => 'Produksi',
      MovementType.orderUsage => 'Pesanan',
      MovementType.adjustment => 'Penyesuaian',
      MovementType.waste => 'Bahan rusak',
      MovementType.opname => 'Stock opname',
    };
