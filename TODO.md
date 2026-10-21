# TODO — BuatUsaha (aplikasi HPP & pencatatan usaha)

Checklist pengerjaan, disusun mengikuti roadmap di PRD bagian 12. Diperbarui setiap ada pekerjaan yang selesai.

- **PRD & ERD:** https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e
- **Mockup:** https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- **Desain:** [Design.md](Design.md)

**Terakhir diperbarui:** 21 Oktober 2026
**Posisi sekarang:** MVP selesai dan dipasang di HP. Fase 2a (login Google + sinkron Firestore) selesai dibuat, lulus test dengan Firestore tiruan, dan sudah di `dev`. Berikutnya: pengguna mengaktifkan Authentication › Google, membuat Firestore + memasang `firestore.rules`, lalu mencoba login di HP; uji pakai sendiri berjalan.

Tanda: `[x]` selesai · `[ ]` belum · "kalkulator ✓" = rumusnya sudah ada dan lulus test di `lib/domain/costing/`, tetapi penyimpanan ke database dan layarnya belum.

## Persiapan (minggu 1)

- [x] PRD & ERD final (pemakaian pribadi, Android saja, Rp0)
- [x] Mockup 10 layar dan Design.md disetujui
- [x] Proyek Flutter + dependensi (Riverpod, drift, go_router, notifikasi lokal, decimal, dll.)
- [x] Skema drift 21 tabel MVP + indeks + foreign key (`lib/data/db/`)
- [x] Kalkulator domain + 44 test lulus: rata-rata tertimbang, HPP + status, upah pemilik, saran harga, kapasitas, kekurangan bahan, nilai stok, stok produk jadi, hitung ulang buku mutasi, potongan channel, ringkasan harian, umur simpan
- [x] Tema dari Design.md (`lib/presentation/theme.dart`), font Plus Jakarta Sans + Fraunces dibundel, navigasi 5 tab
- [x] `git init` + commit pertama (branch `main`; keystore dan `key.properties` di-ignore)
- [x] Signing release di Gradle (`android/key.properties`, contoh di `key.properties.example`) + desugaring untuk notifikasi; build APK release lokal lulus (arm64 18,1 MB)
- [x] Workflow CI `.github/workflows/build-apk.yml`: analyze, test, build APK per ABI; ditandatangani kunci sendiri jika secrets diisi (lihat README)
- [x] Buat keystore `C:\Users\Kanggo L3-038\keys\hpp_app-upload.jks` (PKCS12, alias `upload`, SHA-256 9B:2A:B9:D4:…:1C:93:E4) dari sandi di `android/key.properties`; APK release lokal ditandatangani kunci ini (20 Okt 2026)
- [x] Simpan cadangan keystore dan sandinya di 2 tempat terpisah (dilakukan pengguna, 20 Okt 2026)
- [x] Push ke repo GitHub `ekagalang/BuatUsaha` (branch `main`, sekarang public)
- [x] Run CI pertama lulus: analyze, test, build APK ±10 menit; artefak `hpp-app-apk-debug-signed` (29,8 MB)
- [x] Naikkan versi action di workflow (checkout v7, setup-java v6, upload-artifact v7); teruji saat merge ke `main` atau run manual berikutnya
- [x] Branch `dev` untuk pengerjaan harian; CI hanya berjalan di `main` atau manual (push ke `dev` terbukti tidak memicu CI)
- [x] Isi 4 secrets Android di GitHub (dilakukan pengguna, 20 Okt 2026)
- [x] Verifikasi secrets: run manual Build APK di `dev` (20 Okt 2026, 15.07 WIB) lulus, langkah tanda tangan sukses, artefak `hpp-app-apk`

## Sprint 1 — Bahan dan stok (minggu 2–4)

- [x] Repository bahan + konversi satuan beli bawaan dan khusus (FR-1.1, FR-1.2) — `lib/data/repositories/stock_repository.dart`
- [x] Simpan belanja: purchase + item + mutasi stok + harga rata-rata, dalam satu transaksi DB (FR-1.3)
- [x] Stok awal dan harga perkiraan, mutasi `OPENING`; perkiraan diganti belanja pertama (FR-1.7)
- [x] Penyesuaian stok, stock opname (selisih terhadap saldo pada tanggalnya), bahan rusak (FR-1.4)
- [x] Data kartu stok per bahan, termasuk baris dibatalkan dan pembaliknya (FR-1.5)
- [x] Penanda stok minimum + reset `lowStockNotified` saat stok kembali normal (FR-1.6; notifikasinya di Sprint 3)
- [x] Koreksi transaksi stok bahan: batalkan dengan mutasi pembalik, edit belanja = batalkan + catat ulang, hitung ulang seluruh buku mutasi termasuk belanja bertanggal mundur (FR-9.1–9.3)
- [x] 16 test repository dengan database di memori
- [x] Layar Bahan (nilai modal, saringan menipis/belum ada harga) dan Belanja bahan multi-item dengan pratinjau harga rata-rata (mockup `Bahan`, `FormBelanja`)
- [x] Layar Bahan baru (stok awal / harga perkiraan) dan Detail bahan (penyesuaian, bahan rusak, opname, satuan beli khusus, stok minimum, kartu stok, pembatalan)
- [x] Format Rupiah/angka/tanggal Indonesia, komponen umum, pemilih tanggal berbahasa Indonesia; 65 test lulus
- [x] Layar ubah belanja: tombol "Ubah belanja" di kartu stok, form terisi, pratinjau dampak sebelum disimpan (selesai 20 Okt 2026)
- [x] Peringatan saat mengoreksi tanggal yang sudah Tutup hari (FR-9.6) — selesai di Sprint 4
- [x] Sprint 1 + signing release + CI di-commit dan di-push ke `main`
- [ ] Coba layar Sprint 1 di HP (APK) dan catat masukan

## Sprint 2 — Menu dan HPP (minggu 5–6)

- [x] Repository menu, resep, biaya lain, upah per jam pemilik (FR-2.1–2.3) — `lib/data/repositories/product_repository.dart`
- [x] HPP otomatis + status lengkap/perkiraan/belum lengkap, dihitung ulang saat harga bahan, resep, atau upah berubah (FR-2.4, FR-2.8) — `hpp_refresher.dart`
- [x] Saran harga jual (markup target atau margin 30/40%, dibulatkan) dan peringatan harga di bawah HPP / di bawah target margin (FR-2.5, FR-2.6)
- [x] Tambah bahan baru langsung dari form resep, dengan stok awal atau harga perkiraan (FR-2.7)
- [x] Kapasitas "bisa jadi berapa pcs" + bahan pembatas, kekurangan dan perkiraan belanja untuk target (FR-3.1–3.3)
- [x] Nilai stok produk jadi per menu (FR-3.4); nilai modal sisa bahan sudah di Sprint 1
- [x] Catat produksi: jumlah resep desimal, pemakaian bahan aktual, HPP batch disimpan, ditolak jika stok bahan kurang; batalkan produksi mengembalikan bahan dan stok menu (FR-4.1, FR-4.2, FR-9.1)
- [x] Mode stok per menu (ready stock / pre-order), stok produk jadi rata-rata tertimbang, stok awal produk jadi (FR-4.3–4.5)
- [x] Layar Menu, Detail menu (HPP, saran harga, rincian, kapasitas, simulasi target, stok, riwayat produksi), Ubah resep dengan HPP langsung (mockup `Menu`, `DetailMenu`, `FormResep`)
- [x] 12 test repository menu + 3 widget test layar menu; 80 test lulus
- [x] Penjualan dengan HPP belum lengkap ditandai (FR-2.9) — selesai di Sprint 3
- [x] Penjualan melebihi stok produk jadi (FR-4.9) — selesai di Sprint 3
- [x] Kerugian sisa produk jadi (FR-3.5) — selesai lewat Tutup hari di Sprint 4
- [x] Pengaturan markup bawaan dan pembulatan harga — selesai di Pengaturan, Sprint 4
- [x] Sprint 2 di-commit dan di-push ke `dev`
- [ ] Coba layar Sprint 2 di HP (APK) dan catat masukan

## Sprint 3 — Pesanan dan notifikasi (minggu 7–8)

- [x] Pesanan: pelanggan (dipakai ulang lewat nama/no. WA), item dengan harga bawaan yang bisa diubah, diskon, ongkir, jadwal, ambil/antar, nomor `PO-yyMMdd-NNN` (FR-5.1) — `lib/data/repositories/order_repository.dart`
- [x] Pembayaran DP/pelunasan tunai/transfer/QRIS, sisa tagihan dan status bayar otomatis, pembatalan pembayaran (FR-5.2)
- [x] Status Baru → Diproses → Siap → Selesai, Batal sebelum selesai, tanda Terlambat (FR-5.3)
- [x] Selesai: omzet diakui di tanggal selesai, snapshot HPP (ready stock dari HPP rata-rata stok, pre-order dari HPP terkini atau produksi yang ditautkan), stok menu jadi berkurang, bahan pre-order dipotong (FR-7.1, FR-7.2)
- [x] Laba per pesanan: omzet item − potongan channel − HPP, ditampilkan terpisah (FR-5.6, FR-5.9)
- [x] Penjualan langsung, langsung Selesai dan Lunas (FR-5.7)
- [x] Channel penjualan bawaan (WhatsApp, Instagram, GoFood, GrabFood, ShopeeFood, Shopee) + potongan otomatis yang bisa ditimpa per pesanan (FR-5.8, FR-5.9)
- [x] Kebutuhan produksi untuk tanggal terpilih + bahan yang kurang dan perkiraan belanja (FR-5.5)
- [x] Produksi ditautkan ke pesanan → status Diproses, bahan tidak dipotong dua kali (FR-4.3)
- [x] Penjualan melebihi stok menu jadi ditolak dengan tawaran "Catat produksi" (FR-4.9); item dengan HPP belum lengkap ditandai (FR-2.9)
- [x] Koreksi pesanan selesai: omzet dibalik, refund, barang kembali ke stok atau dicatat dibuang (FR-9.4)
- [x] Notifikasi lokal: pengingat H-1 08.00 dan 2 jam sebelum (bisa diubah/ditambah/dimatikan per pesanan), ringkasan harian, stok menipis sekali per bahan, pengingat pelunasan, jam tenang, deep link ke pesanan/bahan/Tutup hari (FR-6.1–6.6, FR-6.8) — `lib/services/`
- [x] Jadwal notifikasi disusun ulang otomatis setiap data berubah dan tiap 6 jam lewat WorkManager; izin `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` (fallback inexact), boot receiver di manifest, zona waktu perangkat (FR-6.6, FR-6.7)
- [x] Pengingat Tutup hari pukul 20.00 hanya jika ada sisa dan hari belum ditutup, menyebut jumlah yang lewat umur simpan (FR-6.9)
- [x] Layar Pesanan (kalender bulanan + daftar Terlambat/Hari ini/Besok/7 hari, saringan status), Pesanan baru/ubah, Jual langsung, Detail pesanan (mockup `Pesanan`, `FormPesanan`)
- [x] 11 test repository pesanan + 5 test penjadwal notifikasi + 3 widget test layar pesanan; 99 test lulus
- [x] Minta izin notifikasi dan alarm tepat dari layar (onboarding dan Pengaturan, selesai di Sprint 4)
- [x] Panduan izin baterai/autostart untuk Xiaomi, Oppo, Vivo (di Pengaturan, selesai di Sprint 4)
- [x] Koreksi harga bahan menghitung ulang biaya produksi dan stok menu jadi; layar "Koreksi HPP pesanan" + tanda di Beranda untuk menghitung ulang pesanan lama (FR-9.5, selesai 20 Okt 2026)
- [ ] Uji notifikasi di HP sungguhan: tepat waktu ≤ 1 menit dengan alarm tepat, muncul setelah restart dan dalam mode pesawat

## Sprint 4 — Laporan dan persiapan pakai (minggu 9–11)

- [x] Tutup hari: sisa menu ready stock disimpan/dibuang + alasan, kerugian = qty × HPP rata-rata stok, tanda "habis besok"/"lewat umur simpan" (umur dihitung seolah produksi terlama terjual dulu), terlewat = dianggap disimpan, bisa dibatalkan (FR-4.6–4.8, FR-4.10) — `day_close_repository.dart`
- [x] Sisa menu jadi bisa dicatat dibuang kapan saja + kartu stok menu jadi di Detail menu (FR-4.8, PRD 7)
- [x] Ringkasan untung/rugi harian per menu: dibuat, terjual, sisa disimpan/dibuang, omzet, potongan, HPP, rugi sisa, laba, menu yang paling menekan laba; pengeluaran bulanan tidak masuk harian (FR-7.6, FR-7.7) — `report_repository.dart`, contoh PRD (Rp102.950 / Rp82.950) lulus test
- [x] Laporan periode hari/minggu/bulan/rentang: omzet, potongan, HPP, laba kotor + margin, rugi produk dan bahan, pengeluaran, laba bersih, tren harian, menu terlaris dan paling untung, per channel, ongkir terpisah (FR-7.1–7.5, FR-7.8)
- [x] Pengeluaran operasional: kategori bawaan, tanda bulanan, pembatalan (FR-7.3, FR-7.4); skema v2 dengan migrasi (`expenses.is_monthly`, `businesses.onboarded_at`)
- [x] Beranda: status hari ini, catat cepat (pesanan, penjualan, belanja, produksi, pengeluaran, Tutup hari), pesanan hari ini dan besok, laba bulan ini, nilai modal bahan dan menu jadi, perlu perhatian (mockup `Main`)
- [x] Layar Laporan (mockup `Laporan`), Tutup hari (mockup `TutupHari`), Pengeluaran
- [x] Backup ke satu file lewat share sheet dan restore dari file, data lama disimpan `.bak` (FR-8.3)
- [x] Pengaturan: profil usaha, pembulatan, markup bawaan, upah per jam, mode stok bawaan, izin stok minus, notifikasi per jenis + jam ringkasan/Tutup hari + jam tenang, izin notifikasi dan alarm tepat, panduan baterai Xiaomi/Oppo/Vivo/Samsung, channel dan potongannya (FR-6.8, FR-8.1, FR-8.2)
- [x] Onboarding 3 langkah: profil usaha → izin notifikasi → menu pertama (contoh brownies PRD yang bisa diedit, atau buat sendiri) (FR-8.4)
- [x] Peringatan saat mengoreksi tanggal yang sudah Tutup hari (FR-9.6)
- [x] Layar tanpa mockup (detail pesanan, kartu stok menu jadi, pengeluaran, pengaturan, onboarding) dibuat dengan komponen Design.md
- [x] Firebase Crashlytics terpasang; aktif hanya jika `android/app/google-services.json` ada (lokal) atau secret `GOOGLE_SERVICES_JSON_BASE64` diisi (CI) — lihat README
- [x] 108 test lulus (termasuk widget test di lebar layar 360 dp); build APK debug arm64 lulus
- [ ] Buat project Firebase dan pasang `google-services.json` + secret CI (opsional, lihat README)
- [ ] Mode gelap (Design.md: belum didesain)
- [ ] Gerbang: semua FR MVP lulus kriteria penerimaan — dicek saat uji pakai di HP

## Perbaikan setelah MVP (20 Okt 2026)

Desain di-acc lewat mockup baris "Perbaikan, akun & sinkron" di canvas.

- [x] FR-9.5: biaya produksi, HPP stok menu, dan HPP terjual dihitung ulang setelah koreksi harga bahan (`cost_cascade.dart`, `OrderRepository.costCorrections`, layar `cost_correction_screen.dart`); 4 test termasuk kriteria PRD 5.9
- [x] Ubah belanja dengan pratinjau dampak (harga rata-rata, HPP menu, jumlah pesanan terdampak) tanpa menyimpan (`purchase_preview.dart`)
- [x] Detail bahan: bagian "Dipakai di menu" (takaran per resep, bisa jadi berapa pcs, biaya per resep)
- [x] Kolom nominal Rupiah memakai titik ribuan saat mengetik (17 kolom, `rupiah_input.dart`)
- [x] Ikon aplikasi adaptif (cupcake) dan layar pembuka krem; di Android 12+ layar pembuka sistem hanya menampilkan ikon, tanpa teks nama aplikasi
- [x] Backup otomatis harian di HP, 7 terakhir, bisa dipulihkan dari Pengaturan › Data
- [x] Uji huruf 130% di lebar 360 dp untuk 14 layar; 9 tempat teks terpotong diperbaiki
- [x] 132 test lulus
- [x] Di-commit ke `dev` (belum di-push)
- [ ] Ikon PNG lama (mipmap) untuk Android 7.x masih logo Flutter; Android 8+ memakai ikon baru

## Ganti nama jadi BuatUsaha (20 Okt 2026)

- [x] Nama aplikasi "BuatUsaha" (label Android, judul aplikasi, teks backup dan panduan baterai)
- [x] Paket Dart `hpp_app` → `buat_usaha`; ID Android dan namespace `com.hppapp.hpp_app` → `com.ekagalang.buatusaha`; bundle iOS ikut
- [x] File database `buat_usaha.sqlite`, file backup `buatusaha-backup-…`, artefak CI `buatusaha-apk`
- [x] PRD, mockup, README (termasuk cara pindah data dari aplikasi lama), TODO diperbarui
- [x] Folder proyek dipindah ke `Music\ME\App\BuatUsaha` (folder `App` untuk semua proyek aplikasi)
- [x] Di-commit dan di-push ke `dev`
- [ ] Pengguna memindahkan data dari aplikasi lama (lihat README) lalu menghapus aplikasi lama

## Fase 2a — Akun & sinkron Firebase

- [x] PRD/ERD diperbarui: bagian 5.10 (FR-10.x), 11.5, dan perubahan bagian 1, 4, 8, 9, 12, 13, 14 (20 Okt 2026)
- [x] Mockup Pengaturan akun & sinkron di-acc
- [x] Pengguna mengonfirmasi PRD final untuk Firebase (20 Okt 2026)
- [x] Pengguna membuat project Firebase: aplikasi Android `com.ekagalang.buatusaha`, sidik jari SHA-1 kunci release + debug, `google-services.json` di `android/app/` (dicek: paket dan kedua sidik jari benar)
- [ ] Pengguna mengaktifkan Authentication › Google, membuat Cloud Firestore (asia-southeast2) dan menempel `firestore.rules` di tab Rules (README › Firebase)
- [ ] Pengguna mengisi secret CI `GOOGLE_SERVICES_JSON_BASE64` (perintah di README)
- [x] Skema v3: `sync_outbox`, `sync_state`, `businesses.owner_uid`; trigger SQLite sementara mencatat baris yang berubah, kolom cache dan kolom khusus HP tidak memicu kiriman (`lib/data/sync/sync_schema.dart`)
- [x] Mesin sinkron (`sync_engine.dart`): kirim induk dulu dalam batch, tombstone untuk baris terhapus; tarik anak dulu lalu terapkan induk dulu; perubahan terbaru menang (FR-10.2–10.4); cache dihitung ulang setelah tarik (`cache_rebuilder.dart`)
- [x] Bentrok kunci unik dua HP offline: nomor pesanan diberi nomor berikutnya, resep/satuan/pengaturan notifikasi memakai aturan id yang sama di kedua HP; id notifikasi pengingat dibuat sendiri di tiap HP
- [x] Ubah menu dan pesanan memperbarui resep, biaya lain, item, dan pengingat di tempat (id tetap) supaya tidak dobel setelah sinkron; nomor pesanan baru = nomor terbesar + 1
- [x] Login pertama: akun kosong → unggah; HP kosong → unduh (FR-10.6); keduanya berisi → dialog Gabungkan / Pakai data akun dengan backup otomatis dulu (FR-10.5); data HP dari akun yang sama digabung tanpa bertanya
- [x] Login Google (google_sign_in 7 + Firebase Auth), dokumen `users/{uid}`; sinkron otomatis ±15 detik setelah perubahan, saat dibuka/kembali dari latar, tiap 30 menit, tiap 6 jam di WorkManager, coba lagi 30 detik–15 menit (`sync_controller.dart`, `background_tasks.dart`)
- [x] Pengaturan › Akun dan sinkron sesuai mockup `AkunData`: kartu belum masuk / sudah masuk, Tersinkron / Belum terkirim, sinkron terakhir, menunggu dikirim, pesan gagal, Sinkron sekarang (FR-10.7)
- [x] Keluar akun: data tetap di HP atau dihapus dari HP (FR-10.8); dialognya memakai pola dialog mockup `AkunData` (belum ada di mockup)
- [x] Pulihkan backup saat login: isi akun ikut diganti isi backup, tetap jalan walau sempat offline (FR-10.11, baru)
- [x] `firestore.rules` (FR-10.9), README › Firebase dan cara kerja sinkron, PRD 5.10 dan 11.5 diselaraskan
- [x] 152 test lulus: 14 test mesin sinkron dua HP dengan Firestore tiruan, 6 widget test layar akun (termasuk huruf 130% di 360 dp)
- [x] Build APK release lulus dengan `google-services.json` (arm64 25,9 MB, armeabi-v7a 23,8 MB, x86_64 27,3 MB)
- [x] Di-commit dan di-push ke `dev` (21 Okt 2026)
- [ ] Login dari onboarding (FR-10.1 menyebut onboarding; belum ada desainnya)
- [ ] Uji di HP dengan Firebase sungguhan: login, unggah, HP kedua unduh, offline lalu online

## Masuk wajib dengan Google (disetujui 21 Okt 2026)

Login tidak lagi opsional: aplikasi dibuka → layar Masuk dulu, terasa seperti aplikasi komersial.

- [x] PRD diperbarui sebagai usulan: FR-10.1 (masuk wajib, tanpa mode lokal), FR-10.8 (keluar akun menghapus data dan backup otomatis dari HP), FR-10.12 (layar Masuk), FR-10.13 (menyiapkan data), FR-8.4 (onboarding hanya untuk akun baru), catatan sebelum dikomersialkan
- [x] Mockup baris "Masuk wajib dengan Google": `Masuk`, `Menyiapkan`, `AlurMasuk`; `AkunData` diperbarui (kartu belum masuk dihapus, dialog keluar akun baru)
- [x] Pengguna meng-acc PRD dan mockup, termasuk keluar akun menghapus data dari HP (21 Okt 2026)
- [x] Gerbang masuk di router (`accountGate`): layar pembuka → Masuk → Menyiapkan → aplikasi; lokasi tujuan dari notifikasi dibawa lewat layar pembuka
- [x] Layar Masuk (`auth/login_screen.dart`) sesuai mockup: ikon cupcake dan logo Google digambar dari path SVG (`common/brand_marks.dart`), pesan gagal (tanpa internet, dibatalkan, belum tersambung Firebase); tautan Ketentuan/Kebijakan masih snackbar
- [x] Layar Menyiapkan (`auth/prepare_screen.dart`): unduh/unggah dengan progres "x dari y data", dialog Gabungkan / Pakai data akun / Batal dan keluar, akun baru langsung ke onboarding, pulihkan backup → isi akun diganti
- [x] Keluar akun: kirim perubahan dulu, peringatan bila masih ada yang belum terkirim, hapus data usaha + backup otomatis + `.bak`, kembali ke Masuk
- [x] Pengaturan › Akun dan sinkron hanya menampilkan akun yang masuk; restore backup menandai isi akun untuk diganti
- [x] 159 test lulus (alur masuk lengkap lewat aplikasi, keluar akun, huruf 130% untuk layar Masuk dan Menyiapkan)
- [x] Build APK release lulus (arm64 25,9 MB)
- [x] Di-commit dan di-push ke `dev` (21 Okt 2026)
- [ ] Uji di HP: pasang APK baru, masuk dengan Google, data HP terunggah, keluar lalu masuk lagi
- [ ] Sebelum dikomersialkan: Kebijakan privasi dan Ketentuan layanan, menu Hapus akun dan semua data, paket Blaze bila kuota terlewati

## Uji pakai sendiri (minggu 12)

- [x] Build APK release dengan keystore sendiri (arm64 24,8 MB, armeabi-v7a 22,6 MB, x86_64 26,3 MB)
- [x] Pasang APK release di HP (dilakukan pengguna, 20 Okt 2026)
- [ ] Catat paralel dengan cara lama selama 1 minggu
- [ ] Gerbang: selisih laba ≤ Rp1.000/hari dan tanpa crash → dipakai penuh mulai minggu 13

## Fase 2 (minggu 13–18)

- [ ] Kebutuhan bahan dari pesanan mendatang + daftar belanja
- [ ] Riwayat perubahan HPP + simulasi kenaikan harga
- [ ] Sub-resep (adonan dasar) dan paket/hampers
- [ ] Harga jual dan saran harga per channel
- [ ] Nota pesanan via WhatsApp/PDF, ekspor laporan PDF/CSV
- [ ] Arus kas sederhana
- [ ] Backup otomatis ke Google Drive, kunci PIN/biometrik

## Catatan teknis untuk dipantau

- [ ] Plugin `workmanager_android`, `firebase_core`, dan `firebase_crashlytics` masih memakai Kotlin Gradle Plugin; Flutter versi mendatang akan menolak build. Cek versi baru plugin sebelum upgrade Flutter.
- [ ] Jika aplikasi crash di Android 12L ke atas setelah desugaring, tambahkan `androidx.window` (lihat README flutter_local_notifications).

## Fase 3 — opsional (minggu 19–26)

- [ ] Login Supabase + sinkron antar-HP (hanya jika memakai lebih dari satu HP)
- [ ] Multi-user dengan RLS
- [ ] Push FCM via Supabase Cron + Edge Function
