import 'package:decimal/decimal.dart';

import 'money.dart';

enum DayStatus { profit, loss, breakEven }

/// Angka satu menu untuk satu tanggal (FR-7.6).
class ProductDayLine {
  ProductDayLine({
    required this.productId,
    required this.revenue,
    required this.cogs,
    this.channelFee = 0,
    Decimal? wasteLoss,
  }) : wasteLoss = wasteLoss ?? Decimal.zero;

  final String productId;

  /// Omzet item menu ini (tanpa ongkir), dari pesanan yang selesai hari itu.
  final int revenue;

  /// Σ snapshot HPP × qty terjual.
  final Decimal cogs;

  /// Bagian potongan channel untuk item menu ini (lihat allocateProportionally).
  final int channelFee;

  /// Σ qty dibuang × HPP rata-rata stok produk.
  final Decimal wasteLoss;

  Decimal get profit => rupiah(revenue) - rupiah(channelFee) - cogs - wasteLoss;
}

class DaySummary {
  const DaySummary({
    required this.lines,
    required this.revenue,
    required this.channelFee,
    required this.cogs,
    required this.wasteLoss,
    required this.menuProfit,
    required this.expenses,
    required this.materialLoss,
    required this.netProfit,
    required this.status,
    required this.mostPressuringProductId,
  });

  final List<ProductDayLine> lines;
  final int revenue;
  final int channelFee;
  final int cogs;
  final int wasteLoss;

  /// Σ laba per menu = omzet − potongan channel − HPP terjual − rugi sisa.
  final int menuProfit;

  /// Pengeluaran bertanggal hari itu (bukan pengeluaran bulanan).
  final int expenses;

  /// Bahan rusak dan selisih opname hari itu.
  final int materialLoss;
  final int netProfit;
  final DayStatus status;

  /// Menu dengan potongan channel + rugi sisa terbesar; `null` jika tidak ada.
  final String? mostPressuringProductId;
}

/// Ringkasan untung/rugi satu hari (FR-7.6). Hari berstatus untung jika laba
/// semua menu dikurangi pengeluaran dan kerugian bahan hari itu lebih dari 0.
DaySummary summarizeDay({
  required List<ProductDayLine> lines,
  int expenses = 0,
  int materialLoss = 0,
}) {
  var cogs = Decimal.zero;
  var waste = Decimal.zero;
  var menuProfit = Decimal.zero;
  var revenue = 0;
  var fee = 0;
  String? pressuring;
  var worstDeduction = Decimal.zero;
  for (final line in lines) {
    revenue += line.revenue;
    fee += line.channelFee;
    cogs += line.cogs;
    waste += line.wasteLoss;
    menuProfit += line.profit;
    final deduction = rupiah(line.channelFee) + line.wasteLoss;
    if (deduction > worstDeduction) {
      worstDeduction = deduction;
      pressuring = line.productId;
    }
  }
  final net = menuProfit - rupiah(expenses) - rupiah(materialLoss);
  final netProfit = toRupiah(net);
  return DaySummary(
    lines: lines,
    revenue: revenue,
    channelFee: fee,
    cogs: toRupiah(cogs),
    wasteLoss: toRupiah(waste),
    menuProfit: toRupiah(menuProfit),
    expenses: expenses,
    materialLoss: materialLoss,
    netProfit: netProfit,
    status: netProfit > 0
        ? DayStatus.profit
        : netProfit < 0
        ? DayStatus.loss
        : DayStatus.breakEven,
    mostPressuringProductId: pressuring,
  );
}
