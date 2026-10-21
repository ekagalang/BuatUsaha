import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Akun Google yang sedang login (FR-10.1).
class AccountUser {
  const AccountUser({required this.uid, this.name, this.email, this.photoUrl});

  final String uid;
  final String? name;
  final String? email;
  final String? photoUrl;

  /// Huruf untuk avatar (mockup `AkunData`).
  String get initial {
    final source = [
      name,
      email,
      '?',
    ].map((s) => s?.trim() ?? '').firstWhere((s) => s.isNotEmpty);
    return String.fromCharCode(source.runes.first).toUpperCase();
  }
}

/// Login akun; Firebase di aplikasi, tiruan di test.
abstract class AccountGateway {
  AccountUser? get current;
  Stream<AccountUser?> changes();

  /// `null` jika pengguna menutup pilihan akun.
  Future<AccountUser?> signIn();
  Future<void> signOut();
}

/// Login Google lewat Firebase Authentication. Client id web diambil dari
/// `google-services.json` (`default_web_client_id`).
class FirebaseAccountGateway implements AccountGateway {
  FirebaseAccountGateway({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  Future<void>? _init;

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize();

  @override
  AccountUser? get current => _map(_auth.currentUser);

  @override
  Stream<AccountUser?> changes() => _auth.authStateChanges().map(_map);

  @override
  Future<AccountUser?> signIn() async {
    await _ready();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      rethrow;
    }
    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    return _map(result.user);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _ready();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Sesi Google yang tertinggal hanya membuat pilihan akun dilewati.
    }
  }

  static AccountUser? _map(User? user) => user == null
      ? null
      : AccountUser(
          uid: user.uid,
          name: user.displayName,
          email: user.email,
          photoUrl: user.photoURL,
        );
}

/// Pesan kegagalan login atau sinkron yang bisa dipahami pengguna (FR-10.7).
String describeSyncError(Object error) {
  if (error is TimeoutException) {
    return 'Koneksi lambat atau tidak ada internet. Dicoba lagi otomatis.';
  }
  if (error is GoogleSignInException) {
    return switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Login Google belum diatur. Cek SHA-1 di Firebase dan '
            'google-services.json di build ini.',
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Layanan Google di HP ini belum siap. Perbarui Google Play Services.',
      _ => 'Login Google gagal (${error.description ?? error.code.name}).',
    };
  }
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'network-request-failed' => 'Tidak ada internet. Coba lagi nanti.',
      'operation-not-allowed' =>
        'Login Google belum diaktifkan di Firebase Authentication.',
      _ => 'Login gagal (${error.code}).',
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' => 'Tidak ada internet. Dicoba lagi otomatis.',
      'permission-denied' =>
        'Akses ke data akun ditolak. Pastikan Security Rules Firestore '
            'sudah dipasang.',
      'not-found' => 'Database Firestore belum dibuat di Firebase.',
      'resource-exhausted' =>
        'Kuota gratis Firestore hari ini habis. Dicoba lagi besok.',
      _ => 'Sinkron gagal (${error.code}).',
    };
  }
  return 'Sinkron gagal: $error';
}
