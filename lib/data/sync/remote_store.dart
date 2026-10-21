/// Satu baris yang dikirim ke `users/{uid}/{tabel}/{id}` (PRD 11.5).
class RemoteWrite {
  const RemoteWrite({
    required this.table,
    required this.id,
    required this.version,
    this.data,
  });

  final String table;
  final String id;

  /// `_v`: waktu perubahan di HP pengirim (milidetik epoch).
  final int version;

  /// Kolom baris; `null` = baris dihapus (tombstone).
  final Map<String, Object?>? data;
}

/// Satu dokumen baris yang ditarik dari akun.
class RemoteDoc {
  const RemoteDoc({
    required this.id,
    required this.version,
    required this.serverTime,
    this.data,
  });

  final String id;
  final int version;

  /// `_s`: waktu server saat dokumen ditulis; batas tarik berikutnya.
  final DateTime serverTime;
  final Map<String, Object?>? data;

  bool get deleted => data == null;
}

/// Penyimpanan data akun. Firestore di aplikasi, tiruan di dalam memori di
/// test supaya dua HP bisa disimulasikan tanpa internet.
abstract class RemoteStore {
  /// Jumlah tulis terbanyak dalam satu [write].
  int get maxBatch;

  /// Menulis semua [writes] sekaligus (atomik).
  Future<void> write(String uid, List<RemoteWrite> writes);

  /// Dokumen [table] yang ditulis setelah [since] (semua jika `null`),
  /// urut waktu server. [onPage] dipanggil tiap satu halaman dokumen
  /// tertarik, dengan jumlah dokumennya (untuk progres unduh).
  Future<List<RemoteDoc>> changedSince(
    String uid,
    String table,
    DateTime? since, {
    void Function(int count)? onPage,
  });

  /// Jumlah semua dokumen baris di akun, untuk progres unduh.
  Future<int> countAll(String uid);

  /// Id usaha yang tersimpan di akun; kosong = akun belum berisi data.
  Future<List<String>> businessIds(String uid);

  /// Waktu tulis terakhir di akun, untuk dialog login pertama.
  Future<DateTime?> lastWriteAt(String uid);

  /// Dokumen `users/{uid}`: email dan nama akun, dibuat saat login pertama.
  Future<void> saveProfile(String uid, {String? email, String? name});
}
