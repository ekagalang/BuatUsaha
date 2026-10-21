# BuatUsaha

Aplikasi Android untuk usaha makanan rumahan (kue, brownies, katering kecil). Isinya: menghitung HPP per pcs dari resep, mencatat stok bahan dan belanja, mengatur pesanan dan pembayaran, serta melihat untung-rugi harian sampai arus kas. Versi terbaru: **1.3.0**.

- **Jalan tanpa internet.** Semua data tersimpan di HP; internet hanya untuk masuk pertama kali, sinkron, dan cek versi baru.
- **Masuk dengan akun Google.** Data tersalin ke akun, jadi bisa dibuka di HP lain dan tidak hilang saat ganti HP.
- **Biaya Rp0.** Memakai Firebase paket gratis (Spark) dan GitHub gratis. APK dipasang langsung, tanpa Play Store.
- **Angka tidak dihapus diam-diam.** Transaksi yang salah dibatalkan dengan alasan, bukan dihapus, dan laporan menyesuaikan sendiri.

Dokumen lain:

- PRD & ERD: https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e
- Desain: [Design.md](Design.md) · Mockup: https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- Progres pekerjaan: [TODO.md](TODO.md) · Catatan rilis: [CHANGELOG.md](CHANGELOG.md)

## Fitur

Navigasi bawah berisi lima tab: **Beranda, Pesanan, Menu, Bahan, Laporan**. Pengaturan dibuka dari Beranda.

### Beranda

- Status hari ini: omzet, laba, dan pesanan yang harus diselesaikan.
- Catat cepat: pesanan, penjualan langsung, belanja, produksi, pengeluaran, Tutup hari.
- Pesanan hari ini dan besok, laba bulan ini, nilai modal bahan dan menu jadi.
- Perlu perhatian: pesanan terlambat, stok menipis, bahan yang perlu dibeli untuk 3 hari ke depan, HPP pesanan lama yang perlu dihitung ulang.
- Kartu "Versi baru tersedia" bila ada pembaruan aplikasi.

### Pesanan

- Pesanan baru dengan pelanggan (dipakai ulang lewat nama atau nomor WhatsApp), item, diskon, ongkir, jadwal, dan ambil sendiri/diantar. Nomor otomatis `PO-yyMMdd-NNN`.
- Penjualan langsung: langsung tercatat selesai dan lunas.
- Status Baru → Diproses → Siap → Selesai, tanda Terlambat, dan pembatalan.
- Pembayaran DP dan pelunasan (Tunai, Transfer, QRIS, Lainnya); sisa tagihan dan status bayar dihitung otomatis.
- Channel penjualan (WhatsApp, Instagram, GoFood, GrabFood, ShopeeFood, Shopee, atau tambah sendiri). Potongan channel otomatis dan bisa diubah per pesanan. Harga item ikut harga khusus channel itu.
- Laba per pesanan: omzet item − potongan channel − HPP.
- Kalender bulanan dan daftar Terlambat / Hari ini / Besok / 7 hari.
- Kebutuhan produksi untuk tanggal tertentu, bahan yang kurang, dan tombol Buat daftar belanja.
- **Nota:** kirim ke WhatsApp pelanggan, bagikan teks, atau PDF ukuran A6 / struk 58 mm yang bisa dicetak. Isinya memuat logo, alamat, dan info pembayaran usaha.
- Koreksi pesanan yang sudah selesai: omzet dibalik, uang dikembalikan, barang kembali ke stok atau dicatat dibuang.

### Menu dan HPP

- Resep per menu: takaran bahan per resep, hasil berapa pcs, biaya lain (gas, kemasan) per resep atau per pcs, dan jam kerja pemilik × upah per jam.
- HPP per pcs dihitung otomatis dan selalu terbaru setiap harga bahan, resep, atau upah berubah. Statusnya: Lengkap, Perkiraan, atau Belum lengkap.
- Saran harga jual dari markup target atau margin, dibulatkan, dengan peringatan bila harga di bawah HPP atau di bawah target.
- **Harga per channel** dengan saran harga supaya laba per pcs sama dengan jual langsung setelah komisi.
- **Riwayat HPP** dengan grafik dan sebab perubahannya (harga bahan, resep, upah).
- Kapasitas: bisa jadi berapa pcs dari stok sekarang, bahan pembatasnya, dan kekurangan untuk target tertentu.
- **Simulasi harga bahan:** bila harga bahan naik atau turun, terlihat HPP baru, laba, dan saran harga per menu, tanpa menyimpan apa pun.
- Mode stok per menu: **ready stock** (dibuat dulu, stok menu jadi berkurang saat terjual) atau **pre-order** (bahan dipotong saat pesanan selesai). Ready stock bisa punya stok jaga.
- Catat produksi (boleh setengah resep, pemakaian bahan aktual), riwayat produksi, stok menu jadi, dan sisa yang dibuang.

### Bahan dan stok

- Daftar bahan dengan stok, harga rata-rata, nilai modal, saringan menipis atau belum ada harga.
- Satuan beli bawaan (kg, ons, liter, lusin) dan satuan khusus (mis. 1 pack = 200 g).
- Belanja banyak item sekaligus. Harga rata-rata tertimbang dihitung otomatis, dengan pratinjau sebelum disimpan. Pilihan akun kas pembayarnya.
- Stok awal dan harga perkiraan, penyesuaian stok, stock opname, bahan rusak, stok minimum, dan kartu stok per bahan.
- Ubah belanja dengan pratinjau dampaknya ke harga rata-rata, HPP menu, dan pesanan.
- **Daftar belanja otomatis** dari pesanan hari ini, 3 hari, atau 7 hari ke depan, ditambah stok jaga dan stok minimum. Jumlah dibulatkan ke satuan beli dan diberi perkiraan harga. Barang dicentang saat dibeli, lalu dicatat jadi belanja sekali ketuk; daftarnya juga bisa dibagikan ke WhatsApp.

### Laporan, kas, dan ekspor

- Ringkasan harian per menu: dibuat, terjual, sisa disimpan/dibuang, omzet, potongan, HPP, rugi sisa, laba, dan menu yang paling menekan laba.
- Laporan hari, minggu, bulan, atau rentang: omzet, potongan channel, HPP, laba kotor dan margin, rugi produk dan bahan, pengeluaran, laba bersih, tren harian, menu terlaris dan paling untung, per channel, ongkir terpisah.
- Pengeluaran operasional per kategori, termasuk pengeluaran bulanan (sewa, gaji) yang hanya masuk laporan bulanan.
- Tutup hari: sisa menu ready stock disimpan atau dibuang beserta alasannya, dengan tanda lewat umur simpan.
- **Kas:** saldo Tunai, Bank, dan QRIS/e-wallet dihitung otomatis dari pembayaran pesanan, belanja, dan pengeluaran. Catat juga modal masuk, ambil pribadi, pindah antar akun, dan koreksi saldo. Laporan kas bulanan dilengkapi penjelasan kenapa laba berbeda dengan kas.
- **Ekspor:** ringkasan PDF dan empat file CSV (pesanan, item terjual, belanja, pengeluaran) yang langsung rapi di Excel atau Google Sheets.

### Pengaturan, akun, dan data

- Profil usaha: nama, WhatsApp, alamat, logo, info pembayaran, catatan kaki nota, dan ukuran nota.
- Harga: pembulatan saran harga, markup bawaan, dan upah per jam pemilik. Stok: mode stok bawaan dan izin stok minus.
- Channel penjualan beserta komisi dan biaya per pesanan; akun kas dan cara bayar yang masuk ke tiap akun.
- Akun Google dan sinkron, backup ke file, backup otomatis harian (7 terakhir), dan pemulihan.
- Notifikasi per jenis, jam ringkasan dan Tutup hari, jam tenang, serta panduan izin baterai untuk Xiaomi, Oppo, Vivo, dan Samsung.
- Tentang aplikasi: versi, Cek pembaruan, catatan rilis, dan lisensi.

### Notifikasi

- Pengingat pesanan H-1 pukul 08.00 dan 2 jam sebelum jadwal; bisa diubah, ditambah, atau dimatikan per pesanan.
- Ringkasan harian, stok menipis (sekali per bahan), pengingat pelunasan, dan pengingat Tutup hari pukul 20.00 bila masih ada sisa.
- Pemberitahuan versi baru. Ketuk notifikasi langsung membuka pesanan, bahan, atau layar yang dimaksud.

### Pembaruan aplikasi

Aplikasi memeriksa versi baru di GitHub Releases. Pembaruan diunduh dan dipasang dari dalam aplikasi, dan data tetap aman karena kunci tanda tangannya sama.

### Tampilan

Perpindahan layar, tab, dan kartu memakai animasi halus. Semua animasi mati bila pengaturan Android "hapus animasi" aktif. Layar diuji di lebar 360 dp dengan huruf 130%.

## Memasang di HP

1. Unduh `BuatUsaha-<versi>-arm64-v8a.apk` dari [Releases](https://github.com/ekagalang/BuatUsaha/releases/latest). Untuk HP 32-bit lama, pakai `armeabi-v7a`.
2. Buka filenya dan izinkan "pasang dari sumber ini" bila diminta.
3. Masuk dengan Google, isi profil usaha, dan buat menu pertama; contoh brownies tersedia dan bisa diedit.
4. Versi berikutnya muncul sendiri sebagai kartu di Beranda dan notifikasi, lalu tinggal **Unduh dan pasang**.

## Riwayat versi

Salinan dari [CHANGELOG.md](CHANGELOG.md). Saat rilis, CHANGELOG.md tetap menjadi sumbernya, jadi perbarui keduanya.

### 1.3.0 (21 Oktober 2026)

- Harga jual per channel (GoFood, GrabFood, dll.) dengan saran harga supaya laba sama dengan jual langsung
- Pesanan lewat channel otomatis memakai harga channel
- Riwayat HPP per menu dengan grafik dan sebab perubahannya
- Simulasi kenaikan harga bahan: HPP, laba, dan saran harga baru per menu
- Kas: saldo Tunai, Bank, QRIS/e-wallet dari pembayaran, belanja, dan pengeluaran
- Catat modal masuk, ambil pribadi, pindah akun, dan koreksi saldo
- Laporan kas bulanan dan penjelasan kenapa laba beda dengan kas

### 1.2.0 (21 Oktober 2026)

- Nota pesanan: kirim ke WhatsApp pelanggan, bagikan teks, atau PDF ukuran A6/struk 58 mm
- Nota memuat logo, alamat, dan info pembayaran usaha; tanda LUNAS bila sudah dibayar
- Profil usaha: logo, alamat, info pembayaran, catatan kaki nota, ukuran nota
- Ekspor laporan periode: ringkasan PDF dan data CSV (pesanan, item terjual, belanja, pengeluaran) untuk Excel/Sheets
- Cetak nota dan laporan lewat layanan cetak Android

### 1.1.0 (21 Oktober 2026)

- Daftar belanja otomatis dari pesanan hari ini, 3 hari, atau 7 hari ke depan
- Stok jaga per menu ready stock dan bahan di bawah stok minimum ikut dihitung
- Jumlah dibulatkan ke satuan beli (mis. 2 pack × 200 g) dengan perkiraan harga
- Centang saat dibeli, lalu catat jadi belanja sekali ketuk
- Tambah barang lain dan bagikan daftar ke WhatsApp
- Kartu Perlu dibeli di Beranda dan Bahan, tombol Buat daftar belanja di Kebutuhan produksi

### 1.0.0 (21 Oktober 2026)

- Masuk dengan akun Google; data tersimpan di HP dan tersinkron ke akunmu, bisa dibuka di HP lain
- HPP per pcs otomatis dari resep, stok bahan dan nilai modal, produksi, stok menu jadi
- Pesanan dan penjualan langsung, channel dan potongannya, pengingat pesanan
- Laporan untung-rugi harian dan bulanan, Tutup hari, pengeluaran
- Backup otomatis harian dan backup ke file
- Pemberitahuan versi baru: unduh dan pasang pembaruan langsung dari aplikasi
- Perpindahan layar, tab, dan kartu yang lebih halus

### Sebelum 1.0.0

Belum ada rilis bernomor; APK dipasang langsung dari build lokal atau CI.

- **19–20 Okt 2026, MVP:** bahan dan stok, menu dan HPP, pesanan dan notifikasi, laporan, Tutup hari, backup, onboarding, Crashlytics.
- **20 Okt 2026, perbaikan setelah MVP:** koreksi harga bahan menghitung ulang HPP produksi dan pesanan, ubah belanja dengan pratinjau, titik ribuan saat mengetik nominal, ikon cupcake, backup otomatis harian.
- **20 Okt 2026, ganti nama:** aplikasi "HPP Usaha" (`com.hppapp.hpp_app`) menjadi BuatUsaha (`com.ekagalang.buatusaha`).
- **21 Okt 2026, akun dan sinkron:** masuk wajib dengan Google, sinkron Firestore antar-HP, keluar akun menghapus data dari HP.

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
& .\tool\build_apk.ps1
```

Skrip ini menjalankan `flutter build apk --release --split-per-abi` dengan nomor build = jumlah commit dan tanggal build, sama seperti CI. Hasilnya ada di `build/app/outputs/flutter-apk/`. Untuk HP Android modern pakai `app-arm64-v8a-release.apk`.

Jangan pasang APK dari `flutter build apk` biasa di atas versi rilis: nomor build-nya 1, jadi Android menolaknya sebagai versi lama.

## Versi dan rilis

- Nama versi ada di `pubspec.yaml` (`version: 1.3.0+1`; angka setelah `+` diabaikan). Naikkan angka terakhir untuk perbaikan (1.3.1), angka tengah untuk fitur baru (1.4.0).
- Tulis perubahannya di [CHANGELOG.md](CHANGELOG.md) dengan judul `## <versi> (<tanggal>)` dan poin `- …`. Poin-poin itu tampil di dialog "Versi baru tersedia" di aplikasi. Salin juga ke bagian Riwayat versi di README ini.
- Terbitkan: **Actions › Build APK › Run workflow**, centang **Terbitkan rilis**. Push ke `main` juga selalu menerbitkan rilis. CI membuat GitHub Release `v<versi>` berisi `BuatUsaha-<versi>-arm64-v8a.apk`, `-armeabi-v7a.apk`, `-x86_64.apk`.
- Rilis gagal bila versi itu sudah pernah dirilis atau CHANGELOG belum berisi bagian versinya; APK tetap ada di Artifacts. Rilis hanya dibuat dari APK bertanda tangan kunci sendiri.
- Aplikasi memeriksa `releases/latest` repo ini (saat dibuka paling sering sekali per 6 jam, tugas latar tiap 6 jam, dan tombol Pengaturan › Tentang aplikasi › Cek pembaruan), lalu menawarkan **Unduh dan pasang**. Pertama kali, Android meminta izin "pasang dari sumber ini". Data tetap aman karena kunci tanda tangannya sama.
- Kalau repo ini dijadikan private, API rilis butuh token; halaman unduh perlu dipindah dulu.

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

Hanya APK terbaru yang disimpan: setelah build berhasil, CI menghapus artefak `buatusaha-apk*` dari run sebelumnya (izin `actions: write` di workflow). Jika build gagal, APK lama tetap ada. Artefak terbaru disimpan 14 hari. Biaya Actions untuk repo public ini Rp0; angka di halaman Billing GitHub dipotong penuh oleh kuota gratis.

## Firebase: akun Google, sinkron, laporan crash

Masuk dengan Google **wajib** saat aplikasi pertama dibuka, jadi `android/app/google-services.json` harus ada di setiap build yang dipasang. Tanpa file itu aplikasi berhenti di layar Masuk dengan pesan "belum tersambung ke Firebase" (APK dari CI tanpa secret `GOOGLE_SERVICES_JSON_BASE64` juga begitu). File itu tidak masuk git karena repo ini public. Semuanya memakai paket Spark (gratis).

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

- **Layar Masuk → Masuk dengan Google.** Akun baru otomatis terdaftar. Masuk pertama kali butuh internet; setelah itu sesi tersimpan dan aplikasi bisa dibuka tanpa internet. Data tetap tersimpan di HP; salinannya ada di Firestore `users/{uid}/{tabel}/{id}`, hanya bisa dibuka akun itu sendiri.
- Setelah masuk, layar **Menyiapkan** mengunduh data akun (HP baru), mengunggah data HP (pengguna versi lama tanpa akun), menanyakan gabung/ganti bila keduanya berisi data, atau langsung ke onboarding untuk akun baru.
- **Pengaturan › Akun dan sinkron › Keluar dari akun**: perubahan yang tertunda dikirim dulu, lalu data usaha dan backup otomatis dihapus dari HP dan aplikasi kembali ke layar Masuk. Data di akun tetap ada.
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
