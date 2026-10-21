# BuatUsaha

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

Tanpa secrets, artefak CI bernama `buatusaha-apk-debug-signed`.

## Firebase: akun Google, sinkron, laporan crash

Semua fitur Firebase hanya aktif jika `android/app/google-services.json` ada. Tanpa file itu aplikasi tetap jalan penuh dalam mode lokal dan tombol **Masuk dengan Google** tidak aktif. File itu tidak masuk git karena repo ini public. Semuanya memakai paket Spark (gratis).

1. Buka [console.firebase.google.com](https://console.firebase.google.com), **Add project** (Google Analytics boleh dimatikan).
2. **Add app › Android**, package name `com.ekagalang.buatusaha`. Di **Project settings › Your apps** tambahkan dua sidik jari SHA-1: kunci release `F5:A3:09:EF:29:9D:4D:82:8E:CE:12:43:6B:36:6C:0B:A8:26:A0:D0` dan kunci debug (`./gradlew signingReport` di folder `android`). Setelah itu unduh `google-services.json` dan taruh di `android/app/`.
3. **Authentication › Get started › Sign-in method › Google › Enable**, pilih email dukungan, **Save**.
4. **Firestore Database › Create database**: lokasi `asia-southeast2 (Jakarta)`, mode **production**. Lalu buka tab **Rules**, ganti isinya dengan [firestore.rules](firestore.rules), **Publish**.
5. **Crashlytics › Get started** (opsional). Laporan pertama muncul setelah aplikasi release dibuka sekali, crash, lalu dibuka lagi. Laporan tidak dikirim dari build debug.
6. Untuk CI, simpan isi `google-services.json` sebagai secret `GOOGLE_SERVICES_JSON_BASE64` (jalankan dari folder proyek):

```bash
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\android\app\google-services.json")) | Set-Clipboard
```

Jika `google-services.json` diunduh ulang (mis. setelah menambah SHA-1), ganti juga secret CI-nya.

### Cara kerja sinkron

- **Pengaturan › Akun dan sinkron › Masuk dengan Google.** Data tetap tersimpan di HP; salinannya ada di Firestore `users/{uid}/{tabel}/{id}`, hanya bisa dibuka akun itu sendiri.
- Perubahan dikirim ±15 detik setelah tersimpan. Perubahan dari HP lain ditarik saat aplikasi dibuka, kembali dari latar, tiap 30 menit selama dibuka, dan tiap 6 jam di latar belakang. Tanpa internet perubahan menunggu di antrean, lalu dicoba lagi otomatis.
- Konflik per baris: perubahan terbaru menang. Stok, harga rata-rata, HPP, dan sisa tagihan dihitung ulang di tiap HP dari buku mutasinya.
- Login pertama: akun kosong → data HP diunggah; HP kosong → data akun diunduh; keduanya berisi data → pilih **Gabungkan keduanya** atau **Pakai data akun** (data HP dicadangkan dulu ke backup otomatis hari ini).
- Dua HP yang offline membuat pesanan di tanggal yang sama: nomor pesanan yang bentrok diberi nomor berikutnya, sama di kedua HP.
- **Pulihkan** backup saat login: isi akun ikut diganti isi backup, supaya data yang dipulihkan tidak tertimpa lagi.
- Kuota gratis Firestore 50.000 baca dan 20.000 tulis per hari, jauh di atas pemakaian satu usaha.

## Backup data

**Pengaturan › Backup ke file** membagikan satu file `.sqlite` (simpan ke Google Drive atau WhatsApp sendiri); **Pulihkan dari file** memulihkannya dan menyimpan data lama sebagai `.bak` di folder aplikasi. Backup otomatis harian (7 terakhir) ada di **Pengaturan › Backup otomatis di HP**. Sinkron akun Google tidak menggantikan backup: salah input ikut tersinkron ke semua HP.

## Pindah dari aplikasi lama "HPP Usaha"

ID aplikasi berganti dari `com.hppapp.hpp_app` menjadi `com.ekagalang.buatusaha` (20 Okt 2026), jadi Android memasang BuatUsaha sebagai aplikasi baru di samping yang lama:

1. Di aplikasi lama: **Pengaturan › Data › Backup: bagikan file data**, simpan filenya ke Google Drive atau WhatsApp sendiri.
2. Pasang APK BuatUsaha, pilih **Lewati, ke Beranda** di onboarding, lalu **Pengaturan › Data › Pulihkan dari file** dan pilih file tadi.
3. Setelah datanya lengkap, hapus aplikasi lama supaya pengingatnya tidak muncul dua kali.

Kunci tanda tangan tetap sama (`hpp_app-upload.jks`), jadi sidik jari SHA-1 untuk Firebase tidak berubah.
