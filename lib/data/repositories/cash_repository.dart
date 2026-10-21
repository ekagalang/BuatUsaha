import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Akun bawaan (FR-15.1). Id tetap per usaha supaya dua HP yang sama-sama
/// membuat akun bawaan tidak menghasilkan akun ganda setelah sinkron.
const _defaults = [
  (
    'tunai',
    'Tunai',
    CashAccountKind.cash,
    [PaymentMethod.cash, PaymentMethod.other],
  ),
  ('bank', 'Bank', CashAccountKind.bank, [PaymentMethod.transfer]),
  ('qris', 'QRIS/e-wallet', CashAccountKind.ewallet, [PaymentMethod.qris]),
];

String defaultCashAccountId(String businessId) => '$businessId-tunai';

Set<PaymentMethod> paymentMethodsOf(CashAccount account) => {
  for (final code in account.paymentMethods.split(','))
    for (final m in PaymentMethod.values)
      if (m.code == code.trim()) m,
};

enum CashSource {
  payment,
  refund,
  purchase,
  expense,
  capitalIn,
  ownerDraw,
  transferIn,
  transferOut,
  adjustment,
}

/// Satu mutasi kas, dari transaksi atau catatan manual. [amount] bertanda:
/// positif masuk, negatif keluar.
class CashMovement {
  const CashMovement({
    required this.at,
    required this.accountId,
    required this.amount,
    required this.source,
    required this.label,
    this.entryId,
  });

  final DateTime at;
  final String accountId;
  final int amount;
  final CashSource source;
  final String label;

  /// Diisi untuk catatan manual (bisa dibatalkan).
  final String? entryId;

  bool get isTransfer =>
      source == CashSource.transferIn || source == CashSource.transferOut;
}

class CashBalance {
  const CashBalance(this.account, this.balance);

  final CashAccount account;
  final int balance;
}

class CashDay {
  CashDay(this.day);

  final DateTime day;
  var inflow = 0;
  var outflow = 0;
}

/// Kas satu periode (FR-15.4): saldo sekarang, masuk/keluar, per hari, dan
/// mutasinya. Pindah antar akun tidak dihitung sebagai masuk/keluar.
class CashPeriod {
  const CashPeriod({
    required this.from,
    required this.to,
    required this.balances,
    required this.movements,
    required this.days,
    required this.inflow,
    required this.outflow,
  });

  final DateTime from;
  final DateTime to;
  final List<CashBalance> balances;

  /// Terbaru dulu.
  final List<CashMovement> movements;

  /// Terbaru dulu, hanya hari yang ada mutasinya.
  final List<CashDay> days;
  final int inflow;
  final int outflow;

  int get net => inflow - outflow;
  int get total => balances.fold(0, (s, b) => s + b.balance);
}

/// Akun kas, catatan kas manual, dan saldo yang dihitung dari pembayaran,
/// belanja, pengeluaran, dan catatan manual (S5). Saldo tidak disimpan.
class CashRepository {
  CashRepository(this._db);

  final AppDatabase _db;

  DateTime _now() => DateTime.now().toUtc();

  /// Akun bawaan dibuat bila usaha belum punya akun sama sekali.
  Future<void> ensureDefaults(String businessId) async {
    final any =
        await (_db.select(_db.cashAccounts)
              ..where((t) => t.businessId.equals(businessId))
              ..limit(1))
            .getSingleOrNull();
    if (any != null) return;
    for (final (i, (key, name, kind, methods)) in _defaults.indexed) {
      await _db
          .into(_db.cashAccounts)
          .insertOnConflictUpdate(
            CashAccountsCompanion.insert(
              id: Value('$businessId-$key'),
              businessId: businessId,
              name: name,
              kind: kind,
              paymentMethods: Value(methods.map((m) => m.code).join(',')),
              position: Value(i),
            ),
          );
    }
  }

  Stream<List<CashAccount>> watchAccounts(String businessId) =>
      (_db.select(_db.cashAccounts)
            ..where((t) => t.businessId.equals(businessId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.position),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .watch();

  Future<List<CashAccount>> _accounts(String businessId) =>
      watchAccounts(businessId).first;

  /// Akun penerima [method]; tanpa pemetaan → Tunai (FR-15.2).
  Future<String> accountFor(String businessId, PaymentMethod method) async {
    final accounts = await _accounts(businessId);
    for (final a in accounts) {
      if (a.isActive && paymentMethodsOf(a).contains(method)) return a.id;
    }
    return _fallback(businessId, accounts);
  }

  String _fallback(String businessId, List<CashAccount> accounts) {
    final id = defaultCashAccountId(businessId);
    if (accounts.any((a) => a.id == id)) return id;
    return accounts
            .where((a) => a.kind == CashAccountKind.cash)
            .firstOrNull
            ?.id ??
        accounts.firstOrNull?.id ??
        id;
  }

  /// Tambah ([id] `null`) atau ubah akun. Cara bayar yang dipilih dipindah
  /// dari akun lain: satu cara bayar masuk ke satu akun.
  Future<String> saveAccount(
    String businessId, {
    String? id,
    required String name,
    required CashAccountKind kind,
    int openingBalance = 0,
    DateTime? openingAt,
    Set<PaymentMethod> methods = const {},
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Nama akun wajib diisi.');
    return _db.transaction(() async {
      final accounts = await _accounts(businessId);
      for (final a in accounts) {
        if (a.id == id) continue;
        if (a.name.trim().toLowerCase() == trimmed.toLowerCase()) {
          throw ArgumentError('Akun "$trimmed" sudah ada.');
        }
        final own = paymentMethodsOf(a);
        if (own.intersection(methods).isNotEmpty) {
          await (_db.update(
            _db.cashAccounts,
          )..where((t) => t.id.equals(a.id))).write(
            CashAccountsCompanion(
              paymentMethods: Value(_codes(own.difference(methods))),
              updatedAt: Value(_now()),
            ),
          );
        }
      }
      final values = CashAccountsCompanion(
        name: Value(trimmed),
        kind: Value(kind),
        openingBalance: Value(openingBalance),
        openingAt: Value(openingAt?.toUtc()),
        paymentMethods: Value(_codes(methods)),
        updatedAt: Value(_now()),
      );
      if (id != null) {
        await (_db.update(
          _db.cashAccounts,
        )..where((t) => t.id.equals(id))).write(values);
        return id;
      }
      final row = await _db
          .into(_db.cashAccounts)
          .insertReturning(
            values.copyWith(
              businessId: Value(businessId),
              position: Value(accounts.length),
            ),
          );
      return row.id;
    });
  }

  static String _codes(Set<PaymentMethod> methods) => [
    for (final m in PaymentMethod.values)
      if (methods.contains(m)) m.code,
  ].join(',');

  /// Akun tidak dihapus supaya mutasi lamanya tetap terbaca; nonaktif =
  /// tidak muncul di pilihan.
  Future<void> setActive(String id, {required bool active}) =>
      (_db.update(_db.cashAccounts)..where((t) => t.id.equals(id))).write(
        CashAccountsCompanion(
          isActive: Value(active),
          updatedAt: Value(_now()),
        ),
      );

  /// Catatan manual (FR-15.3). [amount] > 0, kecuali koreksi (≠ 0).
  Future<String> addEntry(
    String businessId, {
    required CashEntryKind kind,
    required String accountId,
    String? toAccountId,
    required int amount,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (kind == CashEntryKind.adjustment ? amount == 0 : amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'nominal tidak valid');
    }
    if (kind == CashEntryKind.transfer &&
        (toAccountId == null || toAccountId == accountId)) {
      throw ArgumentError('Pilih akun tujuan yang berbeda.');
    }
    final row = await _db
        .into(_db.cashEntries)
        .insertReturning(
          CashEntriesCompanion.insert(
            businessId: businessId,
            kind: kind,
            accountId: accountId,
            toAccountId: Value(
              kind == CashEntryKind.transfer ? toAccountId : null,
            ),
            amount: amount,
            occurredAt: occurredAt.toUtc(),
            note: Value(
              note == null || note.trim().isEmpty ? null : note.trim(),
            ),
          ),
        );
    return row.id;
  }

  /// Koreksi saldo: catat selisih antara [actual] dan saldo tercatat pada
  /// [at]. `null` bila saldo sudah sama.
  Future<String?> adjustTo(
    String businessId, {
    required String accountId,
    required int actual,
    required DateTime at,
    String? note,
  }) async {
    final balances = await balancesAt(businessId, at);
    final current =
        balances.where((b) => b.account.id == accountId).firstOrNull?.balance ??
        0;
    final diff = actual - current;
    if (diff == 0) return null;
    return addEntry(
      businessId,
      kind: CashEntryKind.adjustment,
      accountId: accountId,
      amount: diff,
      occurredAt: at,
      note: note,
    );
  }

  Future<void> voidEntry(String id, {required String reason}) =>
      (_db.update(_db.cashEntries)..where((t) => t.id.equals(id))).write(
        CashEntriesCompanion(
          voidedAt: Value(_now()),
          voidReason: Value(reason),
          updatedAt: Value(_now()),
        ),
      );

  /// Semua mutasi yang berlaku (setelah tanggal saldo awal akunnya),
  /// terbaru dulu.
  Future<List<CashMovement>> movements(String businessId) async {
    final accounts = await _accounts(businessId);
    final byId = {for (final a in accounts) a.id: a};
    final fallback = _fallback(businessId, accounts);
    final mapping = <PaymentMethod, String>{};
    for (final m in PaymentMethod.values) {
      mapping[m] = fallback;
      for (final a in accounts) {
        if (a.isActive && paymentMethodsOf(a).contains(m)) {
          mapping[m] = a.id;
          break;
        }
      }
    }
    String resolve(String? id, String otherwise) =>
        id != null && byId.containsKey(id) ? id : otherwise;

    final list = <CashMovement>[];

    final payments =
        await (_db.select(_db.payments).join([
              innerJoin(
                _db.orders,
                _db.orders.id.equalsExp(_db.payments.orderId),
              ),
            ])..where(
              _db.orders.businessId.equals(businessId) &
                  _db.payments.voidedAt.isNull(),
            ))
            .get();
    for (final r in payments) {
      final p = r.readTable(_db.payments);
      final o = r.readTable(_db.orders);
      final refund = p.kind == PaymentKind.refund;
      list.add(
        CashMovement(
          at: p.paidAt,
          accountId: resolve(p.cashAccountId, mapping[p.method]!),
          amount: refund ? -p.amount : p.amount,
          source: refund ? CashSource.refund : CashSource.payment,
          label: '${refund ? 'Uang kembali' : 'Pembayaran'} ${o.orderNo}',
        ),
      );
    }

    final purchases =
        await (_db.select(_db.purchases)..where(
              (t) => t.businessId.equals(businessId) & t.voidedAt.isNull(),
            ))
            .get();
    for (final p in purchases) {
      if (p.totalAmount == 0) continue;
      list.add(
        CashMovement(
          at: p.purchasedAt,
          accountId: resolve(p.cashAccountId, fallback),
          amount: -p.totalAmount,
          source: CashSource.purchase,
          label: 'Belanja bahan',
        ),
      );
    }

    final expenses =
        await (_db.select(_db.expenses).join([
              innerJoin(
                _db.expenseCategories,
                _db.expenseCategories.id.equalsExp(_db.expenses.categoryId),
              ),
            ])..where(
              _db.expenses.businessId.equals(businessId) &
                  _db.expenses.voidedAt.isNull(),
            ))
            .get();
    for (final r in expenses) {
      final e = r.readTable(_db.expenses);
      list.add(
        CashMovement(
          at: e.spentAt,
          accountId: resolve(e.cashAccountId, fallback),
          amount: -e.amount,
          source: CashSource.expense,
          label: 'Pengeluaran · ${r.readTable(_db.expenseCategories).name}',
        ),
      );
    }

    final entries =
        await (_db.select(_db.cashEntries)..where(
              (t) => t.businessId.equals(businessId) & t.voidedAt.isNull(),
            ))
            .get();
    for (final e in entries) {
      final note = e.note == null ? '' : ' · ${e.note}';
      final account = resolve(e.accountId, fallback);
      switch (e.kind) {
        case CashEntryKind.capitalIn:
          list.add(
            CashMovement(
              at: e.occurredAt,
              accountId: account,
              amount: e.amount,
              source: CashSource.capitalIn,
              label: 'Modal masuk$note',
              entryId: e.id,
            ),
          );
        case CashEntryKind.ownerDraw:
          list.add(
            CashMovement(
              at: e.occurredAt,
              accountId: account,
              amount: -e.amount,
              source: CashSource.ownerDraw,
              label: 'Ambil pribadi$note',
              entryId: e.id,
            ),
          );
        case CashEntryKind.adjustment:
          list.add(
            CashMovement(
              at: e.occurredAt,
              accountId: account,
              amount: e.amount,
              source: CashSource.adjustment,
              label: 'Koreksi saldo$note',
              entryId: e.id,
            ),
          );
        case CashEntryKind.transfer:
          final to = resolve(e.toAccountId, fallback);
          list
            ..add(
              CashMovement(
                at: e.occurredAt,
                accountId: account,
                amount: -e.amount,
                source: CashSource.transferOut,
                label: 'Pindah ke ${byId[to]?.name ?? 'akun lain'}$note',
                entryId: e.id,
              ),
            )
            ..add(
              CashMovement(
                at: e.occurredAt,
                accountId: to,
                amount: e.amount,
                source: CashSource.transferIn,
                label: 'Pindah dari ${byId[account]?.name ?? 'akun lain'}$note',
                entryId: e.id,
              ),
            );
      }
    }

    // Mutasi sebelum tanggal saldo awal akunnya sudah termasuk di saldo awal.
    list.removeWhere((m) {
      final opening = byId[m.accountId]?.openingAt;
      return opening != null && m.at.isBefore(opening);
    });
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  /// Saldo tiap akun sampai [at] (termasuk).
  Future<List<CashBalance>> balancesAt(String businessId, DateTime at) async {
    final accounts = await _accounts(businessId);
    final sums = <String, int>{};
    for (final m in await movements(businessId)) {
      if (m.at.isAfter(at.toUtc())) continue;
      sums[m.accountId] = (sums[m.accountId] ?? 0) + m.amount;
    }
    return [
      for (final a in accounts)
        if (a.isActive || (sums[a.id] ?? 0) != 0)
          CashBalance(a, a.openingBalance + (sums[a.id] ?? 0)),
    ];
  }

  /// `[from, to)` waktu lokal; saldo dihitung sampai sekarang.
  Future<CashPeriod> period(
    String businessId,
    DateTime from,
    DateTime to,
  ) async {
    final all = await movements(businessId);
    final inRange = [
      for (final m in all)
        if (!m.at.isBefore(from.toUtc()) && m.at.isBefore(to.toUtc())) m,
    ];
    final days = <DateTime, CashDay>{};
    var inflow = 0, outflow = 0;
    for (final m in inRange) {
      if (m.isTransfer) continue;
      final local = m.at.toLocal();
      final day = days.putIfAbsent(
        DateTime(local.year, local.month, local.day),
        () => CashDay(DateTime(local.year, local.month, local.day)),
      );
      if (m.amount >= 0) {
        inflow += m.amount;
        day.inflow += m.amount;
      } else {
        outflow -= m.amount;
        day.outflow -= m.amount;
      }
    }
    return CashPeriod(
      from: from,
      to: to,
      balances: await balancesAt(businessId, DateTime.now()),
      movements: inRange,
      days: days.values.toList()..sort((a, b) => b.day.compareTo(a.day)),
      inflow: inflow,
      outflow: outflow,
    );
  }

  Stream<CashPeriod> watchPeriod(
    String businessId,
    DateTime from,
    DateTime to,
  ) async* {
    yield await period(businessId, from, to);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.payments,
        _db.orders,
        _db.purchases,
        _db.expenses,
        _db.cashEntries,
        _db.cashAccounts,
      ]),
    )) {
      yield await period(businessId, from, to);
    }
  }
}
