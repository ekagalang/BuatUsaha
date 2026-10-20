# hpp_app

Aplikasi Android pribadi untuk menghitung HPP, mencatat stok bahan, laba harian per menu, dan jadwal pesanan. Berjalan offline; biaya Rp0.

- PRD & ERD: https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e
- Desain: [Design.md](Design.md) · Mockup: https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- Progres: [TODO.md](TODO.md)

## Pengembangan

```bash
flutter pub get
dart run build_runner build   # setelah mengubah tabel di lib/data/db/tables
flutter analyze
flutter test
```

## Kunci tanda tangan APK

Semua update harus ditandatangani dengan kunci yang sama. Jika kunci hilang, update tidak bisa dipasang di atas versi lama, dan menghapus aplikasi ikut menghapus datanya.

1. Buat keystore sekali saja, di luar folder proyek (mis. `C:\Users\<nama>\keys\hpp_app-upload.jks`), dengan `keytool` dari Android Studio:

   ```bash
   "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore C:\Users\<nama>\keys\hpp_app-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Salin `android/key.properties.example` menjadi `android/key.properties` lalu isi path dan sandinya. File ini dan semua `*.jks` diabaikan git.
3. Simpan salinan keystore dan sandinya di dua tempat (mis. Google Drive dan flashdisk).

Tanpa `android/key.properties`, build release memakai kunci debug dan Gradle menampilkan peringatan. APK seperti itu boleh dicoba, tetapi jangan dipasang permanen.

## Build APK

```bash
flutter build apk --release --split-per-abi
```

Hasilnya ada di `build/app/outputs/flutter-apk/`. Untuk HP Android modern pakai `app-arm64-v8a-release.apk`.

## CI (GitHub Actions)

`.github/workflows/build-apk.yml` menjalankan analyze, test, dan build APK. APK bisa diunduh dari bagian Artifacts di halaman run.

Alur branch:

- Pengerjaan harian di-commit dan di-push ke `dev`. Branch ini **tidak** memicu CI.
- CI berjalan saat `dev` di-merge/di-push ke `main`, atau saat dijalankan manual lewat **Actions › Build APK › Run workflow** (branch bisa dipilih, termasuk `dev`).

Agar APK dari CI ditandatangani dengan kunci sendiri, isi secrets di **Settings › Secrets and variables › Actions**:

| Secret | Isi |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Isi file `.jks` dalam base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Sandi keystore |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | Sandi kunci (sama dengan sandi keystore) |

Membuat base64 dari keystore di PowerShell:

```bash
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\<nama>\keys\hpp_app-upload.jks")) | Set-Clipboard
```

Tanpa secrets, artefak CI bernama `hpp-app-apk-debug-signed`.

## Laporan crash (Firebase Crashlytics, opsional)

Aplikasi tetap jalan tanpa ini; Crashlytics hanya aktif jika `android/app/google-services.json` ada. File itu tidak masuk git karena repo ini public.

1. Buka [console.firebase.google.com](https://console.firebase.google.com), **Add project** (Google Analytics boleh dimatikan; paket Spark gratis).
2. Di project itu pilih **Add app › Android**, isi package name `com.hppapp.hpp_app`, lalu unduh `google-services.json`.
3. Taruh file itu di `android/app/google-services.json` untuk build lokal.
4. Di menu **Crashlytics**, klik **Get started**. Laporan pertama muncul setelah aplikasi release dibuka sekali, crash, lalu dibuka lagi.
5. Untuk CI, simpan isinya sebagai secret `GOOGLE_SERVICES_JSON_BASE64`:

```bash
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\google-services.json")) | Set-Clipboard
```

Laporan crash tidak dikirim dari build debug.

## Backup data

Data hanya ada di HP. **Pengaturan › Data › Backup** membagikan satu file `.sqlite` (simpan ke Google Drive atau WhatsApp sendiri); **Restore** memulihkannya dan menyimpan data lama sebagai `.bak` di folder aplikasi.
