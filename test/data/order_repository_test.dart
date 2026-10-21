import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/data/db/app_database.dart';
import 'package:buat_usaha/data/repositories/order_repository.dart';

import '../support/seed.dart';

void main() {
  late Seed s;

  setUp(() async => s = await Seed.create());
  tearDown(() => s.close());

  DateTime local(int day, [int hour = 10]) => DateTime(2026, 10, day, hour);

  OrderInput tenBrownies({
    String? channelId,
    int? fee,
    DateTime? due,
    List<ReminderInput>? reminders,
    String? productId,
  }) => OrderInput(
    dueAt: due ?? local(21),
    customerName: 'Bu Rina',
    customerPhone: '08123',
    channelId: channelId,
    channelFee: fee,
    reminders: reminders,
    items: [
      OrderItemInput(
        productId: productId ?? s.brownies,
        qty: 10,
        unitPrice: 8000,
      ),
    ],
  );

  Future<void> make(String batches) => s.products.recordProduction(
    s.brownies,
    batchQty: d(batches),
    at: DateTime.utc(2026, 10, 15),
  );

  test('laba pesanan lewat channel 20% vs langsung (kriteria FR-5)', () async {
    await make('1.5');
    final mitra = await s.channel('Mitra 20%', '20');
    final viaApp = await s.orders.createOrder(
      s.businessId,
      tenBrownies(channelId: mitra),
    );
    var view = await s.orders.loadOrder(viaApp);
    expect(view.order.orderNo, 'PO-261021-001');
    expect(view.itemsRevenue, 80000);
    expect(view.order.channelFee, 16000);
    expect(view.cogs, 48350);
    expect(view.profit, 15650);
    expect(view.title, 'Bu Rina');

    await s.orders.completeOrder(viaApp, at: DateTime.utc(2026, 10, 21, 3));
    view = await s.orders.loadOrder(viaApp);
    expect(view.order.status, OrderStatus.completed);
    expect(view.lines.single.item.hppPerPcsSnapshot, 4835);
    expect(view.profit, 15650);
    expect((await s.product(s.brownies)).stock, d('20'));

    final direct = await s.orders.recordDirectSale(
      s.businessId,
      OrderInput(
        dueAt: DateTime.utc(2026, 10, 21, 5),
        items: [
          OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
        ],
      ),
    );
    view = await s.orders.loadOrder(direct);
    expect(view.order.orderNo, startsWith('JL-261021-'));
    expect(view.order.status, OrderStatus.completed);
    expect(view.order.paymentStatus, PaymentStatus.paid);
    expect(view.profit, 31650);
    expect((await s.product(s.brownies)).stock, d('10'));
  });

  test('nomor pesanan berurutan per hari', () async {
    final a = await s.orders.createOrder(s.businessId, tenBrownies());
    final b = await s.orders.createOrder(s.businessId, tenBrownies());
    final c = await s.orders.createOrder(
      s.businessId,
      tenBrownies(due: local(22)),
    );
    expect((await s.orders.loadOrder(a)).order.orderNo, 'PO-261021-001');
    expect((await s.orders.loadOrder(b)).order.orderNo, 'PO-261021-002');
    expect((await s.orders.loadOrder(c)).order.orderNo, 'PO-261022-001');
  });

  test('DP, pelunasan, dan pembatalan pembayaran', () async {
    final id = await s.orders.createOrder(
      s.businessId,
      OrderInput(
        dueAt: local(21),
        shippingFee: 10000,
        discount: 5000,
        items: [
          OrderItemInput(productId: s.brownies, qty: 10, unitPrice: 8000),
        ],
      ),
    );
    var order = (await s.orders.loadOrder(id)).order;
    expect(order.subtotal, 80000);
    expect(order.total, 85000);
    expect(order.paymentStatus, PaymentStatus.unpaid);

    await s.orders.addPayment(
      id,
      amount: 30000,
      method: PaymentMethod.transfer,
    );
    var view = await s.orders.loadOrder(id);
    expect(view.order.paymentStatus, PaymentStatus.partial);
    expect(view.remaining, 55000);

    final settle = await s.orders.addPayment(
      id,
      amount: 55000,
      method: PaymentMethod.qris,
      kind: PaymentKind.settlement,
    );
    expect(
      (await s.orders.loadOrder(id)).order.paymentStatus,
      PaymentStatus.paid,
    );

    await s.orders.voidPayment(settle, reason: 'salah catat');
    view = await s.orders.loadOrder(id);
    expect(view.order.paidAmount, 30000);
    expect(view.order.paymentStatus, PaymentStatus.partial);
    expect(view.payments, hasLength(2));
  });

  test(
    'stok menu jadi kurang → ditolak dan ditawarkan produksi (FR-4.9)',
    () async {
      final id = await s.orders.createOrder(s.businessId, tenBrownies());
      await expectLater(
        s.orders.completeOrder(id),
        throwsA(
          isA<InsufficientProductStockException>().having(
            (e) => e.shortages,
            'shortages',
            {'Brownies': d('10')},
          ),
        ),
      );
      expect((await s.orders.loadOrder(id)).order.status, OrderStatus.newOrder);
    },
  );

  test('menu pre-order: bahan dipotong saat selesai, HPP terkini', () async {
    final cake = await s.products.createProduct(
      s.businessId,
      s.browniesInput(mode: StockDeductMode.onComplete, name: 'Brownies PO'),
    );
    final id = await s.orders.createOrder(
      s.businessId,
      tenBrownies(productId: cake),
    );
    await s.orders.completeOrder(id, at: DateTime.utc(2026, 10, 21));
    final view = await s.orders.loadOrder(id);
    expect(view.lines.single.item.hppPerPcsSnapshot, 4835);
    expect(view.lines.single.item.hppStatusSnapshot, HppStatus.complete);
    // 10 pcs = 0,5 resep → tepung 125 g.
    expect(await s.ingredientStock('tepung'), d('875'));
    expect((await s.product(cake)).stock, Decimal.zero);
  });

  test('produksi untuk pesanan pre-order: status Diproses, bahan tidak dipotong dua kali', () async {
    final cake = await s.products.createProduct(
      s.businessId,
      s.browniesInput(mode: StockDeductMode.onComplete, name: 'Brownies PO'),
    );
    final id = await s.orders.createOrder(
      s.businessId,
      tenBrownies(productId: cake),
    );
    await s.products.recordProduction(
      cake,
      batchQty: d('0.5'),
      orderId: id,
      at: DateTime.utc(2026, 10, 20),
    );
    expect((await s.orders.loadOrder(id)).order.status, OrderStatus.inProgress);
    expect(await s.ingredientStock('tepung'), d('875'));

    await s.orders.completeOrder(id, at: DateTime.utc(2026, 10, 21));
    expect(await s.ingredientStock('tepung'), d('875'));
    expect(
      (await s.orders.loadOrder(id)).lines.single.item.hppPerPcsSnapshot,
      4835,
    );
  });

  test(
    'pesanan selesai dibatalkan, barang kembali ke stok + refund (FR-9.4)',
    () async {
      await make('1.5');
      final id = await s.orders.createOrder(s.businessId, tenBrownies());
      await s.orders.addPayment(
        id,
        amount: 80000,
        method: PaymentMethod.cash,
        kind: PaymentKind.settlement,
      );
      await s.orders.completeOrder(id, at: DateTime.utc(2026, 10, 21));
      expect((await s.product(s.brownies)).stock, d('20'));

      await s.orders.voidCompletedOrder(
        id,
        reason: 'salah kirim',
        refund: 80000,
      );
      final view = await s.orders.loadOrder(id);
      expect(view.order.status, OrderStatus.cancelled);
      expect(view.order.voidedAt, isNotNull);
      expect(view.order.paidAmount, 0);
      expect(view.payments.last.kind, PaymentKind.refund);
      expect((await s.product(s.brownies)).stock, d('30'));
    },
  );

  test(
    'pesanan selesai dibatalkan dan barangnya dibuang → rugi tercatat',
    () async {
      await make('1.5');
      final id = await s.orders.createOrder(s.businessId, tenBrownies());
      await s.orders.completeOrder(id, at: DateTime.utc(2026, 10, 21));
      await s.orders.voidCompletedOrder(
        id,
        reason: 'rusak di jalan',
        returnToStock: false,
      );
      expect((await s.product(s.brownies)).stock, d('20'));
      final card = await s.products.watchProductCard(s.brownies).first;
      final waste = card.firstWhere((m) => m.type == ProductMovementType.waste);
      expect(waste.value, -48350);
      expect(waste.refType, orderVoidRef);
    },
  );

  test(
    'pengingat bawaan H-1 08.00 dan 2 jam sebelum; ikut jadwal baru',
    () async {
      final id = await s.orders.createOrder(s.businessId, tenBrownies());
      var view = await s.orders.loadOrder(id);
      expect(view.reminders.map((r) => r.kind), [
        ReminderKind.dayBefore,
        ReminderKind.beforeDue,
      ]);
      expect(
        view.reminders.first.remindAt.toLocal(),
        DateTime(2026, 10, 20, 8),
      );
      expect(view.reminders.last.remindAt.toLocal(), DateTime(2026, 10, 21, 8));
      expect(view.reminders.first.notificationId, 1000);

      await s.orders.updateOrder(
        id,
        tenBrownies(
          due: local(23, 16),
          reminders: OrderRepository.remindersOf(view),
        ),
      );
      view = await s.orders.loadOrder(id);
      expect(
        view.reminders.first.remindAt.toLocal(),
        DateTime(2026, 10, 22, 8),
      );
      expect(
        view.reminders.last.remindAt.toLocal(),
        DateTime(2026, 10, 23, 14),
      );

      await s.orders.cancelOrder(id, reason: 'pelanggan batal');
      view = await s.orders.loadOrder(id);
      expect(view.order.status, OrderStatus.cancelled);
      expect(
        view.reminders.every((r) => r.status == ReminderStatus.cancelled),
        isTrue,
      );
      await expectLater(s.orders.completeOrder(id), throwsStateError);
    },
  );

  test('kebutuhan produksi untuk tanggal terpilih (FR-5.5)', () async {
    await make('0.5');
    await s.orders.createOrder(s.businessId, tenBrownies());
    await s.orders.createOrder(
      s.businessId,
      OrderInput(
        dueAt: local(21, 15),
        items: [
          OrderItemInput(productId: s.brownies, qty: 30, unitPrice: 8000),
        ],
      ),
    );
    await s.orders.createOrder(s.businessId, tenBrownies(due: local(22)));

    final needs = await s.orders.productionNeeds(s.businessId, local(21));
    final need = needs.products.single;
    expect(need.orderedQty, 40);
    expect(need.toMake, d('30'));
    // 30 pcs = 1,5 resep; cokelat tersisa 300 − 100 = 200 g, perlu 300 g.
    final cokelat = needs.shortages.single;
    expect(cokelat.ingredient.name, 'Cokelat');
    expect(cokelat.missingQty, d('100'));
    expect(cokelat.estimatedCost, d('15000'));
  });

  test(
    'potongan channel otomatis bisa ditimpa dan pelanggan dipakai ulang',
    () async {
      final mitra = await s.channel('Mitra 20%', '20');
      final a = await s.orders.createOrder(
        s.businessId,
        tenBrownies(channelId: mitra, fee: 12000),
      );
      expect((await s.orders.loadOrder(a)).order.channelFee, 12000);
      expect(await s.orders.suggestedChannelFee(mitra, 80000), 16000);

      final b = await s.orders.createOrder(s.businessId, tenBrownies());
      expect(
        (await s.orders.loadOrder(a)).customer!.id,
        (await s.orders.loadOrder(b)).customer!.id,
      );
      final found = await s.orders.searchCustomers(s.businessId, 'rina');
      expect(found.single.phoneWa, '08123');
      expect(
        (await s.orders.watchChannels(s.businessId).first).map((c) => c.name),
        containsAll(['WhatsApp', 'GoFood', 'Mitra 20%']),
      );
    },
  );
}
