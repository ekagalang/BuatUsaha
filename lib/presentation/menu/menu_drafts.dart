import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_updates.dart' show KeyValueStore;
import '../../services/update_controller.dart' show keyValueStoreProvider;

/// Draf form menu di HP ini, tidak disinkron (FR-20.1). [id] = id menu untuk
/// draf perubahan, atau `baru-<waktu>` untuk menu baru.
class MenuDraft {
  const MenuDraft({
    required this.id,
    required this.savedAt,
    required this.data,
    this.productId,
  });

  factory MenuDraft.fromJson(Map<String, dynamic> json) => MenuDraft(
    id: json['id'] as String,
    productId: json['productId'] as String?,
    savedAt: DateTime.parse(json['savedAt'] as String),
    data: Map<String, dynamic>.from(json['data'] as Map),
  );

  final String id;

  /// Diisi untuk draf perubahan menu yang sudah ada.
  final String? productId;
  final DateTime savedAt;

  /// Isian form apa adanya (teks yang diketik).
  final Map<String, dynamic> data;

  bool get isNew => productId == null;

  String get name {
    final name = (data['name'] as String? ?? '').trim();
    return name.isEmpty ? 'Tanpa nama' : name;
  }

  int get ingredientCount => (data['recipe'] as List? ?? const []).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'savedAt': savedAt.toIso8601String(),
    'data': data,
  };
}

/// Semua draf menu, terbaru dulu. Tidak ada batas jumlah atau umur; draf
/// hilang hanya bila disimpan atau dibuang sendiri.
class MenuDraftsNotifier extends AsyncNotifier<List<MenuDraft>> {
  static const _key = 'menu.drafts';

  @override
  Future<List<MenuDraft>> build() async {
    // Draf hanya kemudahan: penyimpanan yang gagal tidak boleh mengganggu
    // form.
    final String? raw;
    try {
      raw = await ref.read(keyValueStoreProvider).getString(_key);
    } catch (_) {
      return const [];
    }
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final d in jsonDecode(raw) as List)
          MenuDraft.fromJson(Map<String, dynamic>.from(d as Map)),
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } on FormatException {
      return const [];
    }
  }

  Future<List<MenuDraft>> _current() async => state.value ?? await future;

  /// [store] diambil sebelum menunggu apa pun: draf juga disimpan saat form
  /// ditutup, ketika layar (dan provider) bisa sudah dibuang.
  Future<void> _write(KeyValueStore? store, List<MenuDraft> drafts) async {
    final sorted = [...drafts]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (ref.mounted) state = AsyncData(sorted);
    try {
      await store?.setString(
        _key,
        jsonEncode([for (final d in sorted) d.toJson()]),
      );
    } catch (_) {
      // Tetap ada di memori selama aplikasi terbuka.
    }
  }

  KeyValueStore? _store() {
    try {
      return ref.read(keyValueStoreProvider);
    } catch (_) {
      return null;
    }
  }

  Future<List<MenuDraft>> _safeCurrent() async {
    try {
      return await _current();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(MenuDraft draft) async {
    final store = _store();
    final drafts = await _safeCurrent();
    await _write(store, [
      for (final d in drafts)
        if (d.id != draft.id) d,
      draft,
    ]);
  }

  Future<void> remove(String id) async {
    final store = _store();
    final drafts = await _safeCurrent();
    if (!drafts.any((d) => d.id == id)) return;
    await _write(store, [
      for (final d in drafts)
        if (d.id != id) d,
    ]);
  }

  Future<MenuDraft?> find(String id) async {
    for (final d in await _safeCurrent()) {
      if (d.id == id) return d;
    }
    return null;
  }
}

final menuDraftsProvider =
    AsyncNotifierProvider<MenuDraftsNotifier, List<MenuDraft>>(
      MenuDraftsNotifier.new,
    );
