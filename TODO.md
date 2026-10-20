# TODO — Aplikasi HPP & Pencatatan Usaha

Checklist pengerjaan, disusun mengikuti roadmap di PRD bagian 12. Diperbarui setiap ada pekerjaan yang selesai.

- **PRD & ERD:** https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e
- **Mockup:** https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- **Desain:** [Design.md](Design.md)

**Terakhir diperbarui:** 20 Oktober 2026
**Posisi sekarang:** Sprint 3 (pesanan & notifikasi) selesai di branch `dev`; Sprint 1–3 belum dicoba di HP. Dari persiapan masih tersisa keystore dan secrets CI. Berikutnya: Sprint 4 (Tutup hari, laporan, Beranda, pengaturan, backup).

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
- [ ] Buat keystore `C:\Users\Kanggo L3-038\keys\hpp_app-upload.jks`, isi `android/key.properties`, simpan keystore dan sandinya di 2 tempat
- [x] Push ke repo GitHub `ekagalang/BuatUsaha` (branch `main`, sekarang public)
- [x] Run CI pertama lulus: analyze, test, build APK ±10 menit; artefak `hpp-app-apk-debug-signed` (29,8 MB)
- [x] Naikkan versi action di workflow (checkout v7, setup-java v6, upload-artifact v7); teruji saat merge ke `main` atau run manual berikutnya
- [x] Branch `dev` untuk pengerjaan harian; CI hanya berjalan di `main` atau manual (push ke `dev` terbukti tidak memicu CI)
- [ ] Isi 4 secrets Android di GitHub setelah keystore dibuat (lihat README)

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
- [ ] Layar edit belanja (repository `replacePurchase` sudah ada; di UI saat ini batalkan lalu catat ulang)
- [ ] Peringatan saat mengoreksi tanggal yang sudah Tutup hari (FR-9.6) — menunggu Tutup hari di Sprint 4
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
- [ ] Kerugian sisa produk jadi (FR-3.5) — dicatat lewat Tutup hari di Sprint 4
- [ ] Pengaturan markup bawaan dan pembulatan harga (repository `setPricing` sudah ada; layarnya di Pengaturan, Sprint 4)
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
- [ ] Minta izin notifikasi dan alarm tepat dari layar (onboarding/Pengaturan, Sprint 4)
- [ ] Panduan izin baterai/autostart untuk Xiaomi, Oppo, Vivo (di Pengaturan, Sprint 4)
- [ ] Daftar pesanan lama yang terpengaruh koreksi harga bahan + tawaran hitung ulang HPP (FR-9.5)
- [ ] Uji notifikasi di HP sungguhan: tepat waktu ≤ 1 menit dengan alarm tepat, muncul setelah restart dan dalam mode pesawat

## Sprint 4 — Laporan dan persiapan pakai (minggu 9–11)

- [ ] Tutup hari: disimpan/dibuang + alasan, umur simpan (FR-4.6–4.8, FR-4.10) — kalkulator ✓
- [ ] Ringkasan untung/rugi harian per menu (FR-7.6) — kalkulator ✓
- [ ] Laporan periode, per channel, pengeluaran (FR-7.1–7.5, FR-7.7, FR-7.8)
- [ ] Beranda (mockup `Main`) dan Laporan harian (mockup `Laporan`)
- [ ] Backup dan restore ke file (FR-8.3)
- [ ] Pengaturan (FR-8.1, FR-8.2) dan onboarding (FR-8.4)
- [ ] Desain layar yang belum ada (Design.md bagian 14)
- [ ] Firebase Crashlytics
- [ ] Gerbang: semua FR MVP lulus kriteria penerimaan

## Uji pakai sendiri (minggu 12)

- [ ] Build APK release dengan keystore sendiri, pasang di HP
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

- [ ] Plugin `workmanager_android` masih memakai Kotlin Gradle Plugin; Flutter versi mendatang akan menolak build. Cek versi baru plugin sebelum upgrade Flutter.
- [ ] Jika aplikasi crash di Android 12L ke atas setelah desugaring, tambahkan `androidx.window` (lihat README flutter_local_notifications).

## Fase 3 — opsional (minggu 19–26)

- [ ] Login Supabase + sinkron antar-HP (hanya jika memakai lebih dari satu HP)
- [ ] Multi-user dengan RLS
- [ ] Push FCM via Supabase Cron + Edge Function
