# TODO — Aplikasi HPP & Pencatatan Usaha

Checklist pengerjaan, disusun mengikuti roadmap di PRD bagian 12. Diperbarui setiap ada pekerjaan yang selesai.

- **PRD & ERD:** https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e
- **Mockup:** https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- **Desain:** [Design.md](Design.md)

**Terakhir diperbarui:** 20 Oktober 2026
**Posisi sekarang:** Persiapan hampir selesai. Berikutnya: Sprint 1 (bahan & stok).

Tanda: `[x]` selesai · `[ ]` belum · "kalkulator ✓" = rumusnya sudah ada dan lulus test di `lib/domain/costing/`, tetapi penyimpanan ke database dan layarnya belum.

## Persiapan (minggu 1)

- [x] PRD & ERD final (pemakaian pribadi, Android saja, Rp0)
- [x] Mockup 10 layar dan Design.md disetujui
- [x] Proyek Flutter + dependensi (Riverpod, drift, go_router, notifikasi lokal, decimal, dll.)
- [x] Skema drift 21 tabel MVP + indeks + foreign key (`lib/data/db/`)
- [x] Kalkulator domain + 44 test lulus: rata-rata tertimbang, HPP + status, upah pemilik, saran harga, kapasitas, kekurangan bahan, nilai stok, stok produk jadi, hitung ulang buku mutasi, potongan channel, ringkasan harian, umur simpan
- [x] Tema dari Design.md (`lib/presentation/theme.dart`), font Plus Jakarta Sans + Fraunces dibundel, navigasi 5 tab
- [x] `git init` + commit pertama (branch `main`; keystore dan `key.properties` di-ignore)
- [ ] Buat keystore tanda tangan APK, simpan keystore dan sandinya di 2 tempat
- [ ] CI build APK (GitHub Actions, gratis)

## Sprint 1 — Bahan dan stok (minggu 2–4)

- [ ] Repository bahan + konversi satuan beli (FR-1.1, FR-1.2)
- [ ] Simpan belanja: purchase + item + mutasi stok + harga rata-rata, dalam satu transaksi DB (FR-1.3) — kalkulator ✓
- [ ] Stok awal dan harga perkiraan, mutasi `OPENING` (FR-1.7)
- [ ] Penyesuaian stok, stock opname, bahan rusak (FR-1.4)
- [ ] Kartu stok per bahan (FR-1.5)
- [ ] Penanda stok minimum (FR-1.6)
- [ ] Koreksi transaksi: batalkan dengan mutasi pembalik, edit = batalkan + catat ulang, hitung ulang dari tanggal transaksi (FR-9.1–9.3, FR-9.6) — kalkulator ✓
- [ ] Layar Bahan dan Belanja bahan (mockup `Bahan`, `FormBelanja`)

## Sprint 2 — Menu dan HPP (minggu 5–6)

- [ ] Repository menu, resep, biaya lain, upah per jam pemilik (FR-2.1–2.3)
- [ ] HPP otomatis + status lengkap/perkiraan/belum lengkap, dihitung ulang saat harga bahan atau upah berubah (FR-2.4, FR-2.8) — kalkulator ✓
- [ ] Saran harga jual dan peringatan harga (FR-2.5, FR-2.6) — kalkulator ✓
- [ ] Tambah bahan baru langsung dari form resep (FR-2.7)
- [ ] Penjualan dengan HPP belum lengkap ditandai (FR-2.9)
- [ ] Kapasitas "bisa jadi berapa pcs" dan kekurangan untuk target (FR-3.1–3.3) — kalkulator ✓
- [ ] Nilai modal sisa bahan dan stok produk jadi, kerugian (FR-3.4, FR-3.5) — kalkulator ✓
- [ ] Catat produksi, mode stok per menu, stok produk jadi, penjualan melebihi stok (FR-4.1–4.5, FR-4.9) — kalkulator ✓
- [ ] Layar Menu, Detail menu, Ubah resep (mockup `Menu`, `DetailMenu`, `FormResep`)

## Sprint 3 — Pesanan dan notifikasi (minggu 7–8)

- [ ] Pesanan: item, jadwal, pembayaran DP/pelunasan, status, terlambat (FR-5.1–5.4, FR-5.6)
- [ ] Penjualan langsung (FR-5.7)
- [ ] Channel penjualan + potongan per pesanan (FR-5.8, FR-5.9) — kalkulator ✓
- [ ] Kebutuhan produksi untuk tanggal terpilih (FR-5.5)
- [ ] Pembatalan pesanan selesai + refund, hitung ulang HPP pesanan lama (FR-9.4, FR-9.5)
- [ ] Notifikasi lokal: izin `POST_NOTIFICATIONS`, exact alarm + fallback, boot receiver, zona waktu (FR-6.1–6.8)
- [ ] Pengingat Tutup hari (FR-6.9)
- [ ] Panduan izin baterai/autostart untuk Xiaomi, Oppo, Vivo
- [ ] Layar Pesanan dan Pesanan baru (mockup `Pesanan`, `FormPesanan`)

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

## Fase 3 — opsional (minggu 19–26)

- [ ] Login Supabase + sinkron antar-HP (hanya jika memakai lebih dari satu HP)
- [ ] Multi-user dengan RLS
- [ ] Push FCM via Supabase Cron + Edge Function
