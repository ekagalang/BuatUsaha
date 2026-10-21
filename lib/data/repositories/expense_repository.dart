import 'package:drift/drift.dart';

import '../db/app_database.dart';

DateTime _now() => DateTime.now().toUtc();

class ExpenseView {
  const ExpenseView({required this.expense, required this.category});

  final Expense expense;
  final ExpenseCategory category;
}

/// Pengeluaran operasional (FR-7.3). Belanja bahan dan biaya yang sudah
/// masuk HPP tidak dicatat di sini (FR-7.4).
class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  Stream<List<ExpenseCategory>> watchCategories(String businessId) =>
      (_db.select(_db.expenseCategories)
            ..where(
              (t) => t.businessId.equals(businessId) & t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  Future<String> addCategory(String businessId, String name) async {
    if (name.trim().isEmpty) throw ArgumentError('Nama kategori belum diisi.');
    final row = await _db
        .into(_db.expenseCategories)
        .insertReturning(
          ExpenseCategoriesCompanion.insert(
            businessId: businessId,
            name: name.trim(),
          ),
        );
    return row.id;
  }

  Future<String> addExpense(
    String businessId, {
    required String categoryId,
    required int amount,
    required DateTime spentAt,
    bool isMonthly = false,
    String? note,
    String? cashAccountId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'harus > 0');
    final row = await _db
        .into(_db.expenses)
        .insertReturning(
          ExpensesCompanion.insert(
            businessId: businessId,
            categoryId: categoryId,
            amount: amount,
            spentAt: spentAt.toUtc(),
            isMonthly: Value(isMonthly),
            note: Value(note),
            cashAccountId: Value(cashAccountId),
          ),
        );
    return row.id;
  }

  /// Batalkan, bukan hapus (FR-9.1).
  Future<void> voidExpense(String id, {required String reason}) async {
    final expense = await (_db.select(
      _db.expenses,
    )..where((t) => t.id.equals(id))).getSingle();
    if (expense.voidedAt != null) {
      throw StateError('Pengeluaran ini sudah dibatalkan.');
    }
    await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
      ExpensesCompanion(
        voidedAt: Value(_now()),
        voidReason: Value(reason),
        updatedAt: Value(_now()),
      ),
    );
  }

  /// Pengeluaran bertanggal `[from, to)`, terbaru di atas; termasuk yang
  /// dibatalkan agar riwayatnya tetap terlihat.
  Stream<List<ExpenseView>> watchExpenses(
    String businessId, {
    required DateTime from,
    required DateTime to,
  }) {
    final query =
        _db.select(_db.expenses).join([
            innerJoin(
              _db.expenseCategories,
              _db.expenseCategories.id.equalsExp(_db.expenses.categoryId),
            ),
          ])
          ..where(
            _db.expenses.businessId.equals(businessId) &
                _db.expenses.spentAt.isBiggerOrEqualValue(from.toUtc()) &
                _db.expenses.spentAt.isSmallerThanValue(to.toUtc()),
          )
          ..orderBy([OrderingTerm.desc(_db.expenses.spentAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          ExpenseView(
            expense: r.readTable(_db.expenses),
            category: r.readTable(_db.expenseCategories),
          ),
      ],
    );
  }
}
