import 'dart:async';

import 'package:buat_usaha/services/account_service.dart';

const rina = AccountUser(
  uid: 'akun-rina',
  name: 'Rina Kusuma Wardhani Pratiwi',
  email: 'rina.kusuma.wardhani@gmail.com',
);

/// Login Google tiruan. [next] = akun yang dipilih saat masuk; `null` =
/// pengguna menutup pilihan akun.
class FakeAccountGateway implements AccountGateway {
  FakeAccountGateway([this._current, this.next = rina]);

  AccountUser? _current;
  AccountUser? next;
  final _changes = StreamController<AccountUser?>.broadcast();

  @override
  AccountUser? get current => _current;

  @override
  Stream<AccountUser?> changes() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<AccountUser?> signIn() async {
    _current = next;
    if (next != null) _changes.add(_current);
    return next;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }
}
