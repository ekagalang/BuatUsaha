# Design — Aplikasi HPP & Pencatatan Usaha

Spesifikasi desain untuk implementasi Flutter. Disetujui 20 Oktober 2026.

- **Mockup interaktif (10 layar):** https://claude.ai/artifact/MKtkZPSUxqnebpadio2pYR
- **PRD & ERD:** https://claude.ai/code/artifact/4cee3d90-44fd-445d-8a6e-7c3dbf36470e (bagian 7.1 merangkum dokumen ini)

Jika mockup dan dokumen ini berbeda, dokumen ini yang berlaku.

## 1. Arah visual

Hangat ala toko kue: latar krem, aksen cokelat, kartu putih yang tenang. Warna kuat hanya dipakai untuk satu hal per layar (kartu hero atau tombol utama) dan untuk status. Angka uang adalah isi utama aplikasi, jadi tipografinya dibuat besar, tebal, dan tabular.

## 2. Prinsip

1. **Angka terpenting paling besar dan paling atas.** Beranda: laba bersih hari ini. Detail menu: HPP per pcs. Bahan: nilai modal sisa bahan.
2. **Status = teks + warna.** Selalu ada label ("Untung", "Belum lengkap", "Terlambat"); warna hanya penguat.
3. **Satu aksi utama per layar**, di bilah bawah yang selalu terlihat (Simpan pesanan, Simpan Tutup hari, Simpan belanja).
4. **Cepat dicatat.** Transaksi harian ≤ 3 ketukan dari Beranda lewat grid "Catat cepat".
5. **Hitungan terlihat langsung.** Form menampilkan hasil saat diketik: HPP di form resep, laba di form pesanan, harga rata-rata baru di form belanja, rugi sisa di Tutup hari.
6. **Bahasa sehari-hari.** "Menu", bukan "produk"; "Bisa jadi 30 pcs", bukan "kapasitas produksi".

## 3. Warna

| Token | Hex | Dipakai untuk |
| --- | --- | --- |
| `background` | `#FBF6EE` | Latar semua layar |
| `surface` | `#FFFFFF` | Kartu, form, bilah bawah, navigasi bawah |
| `surfaceMuted` | `#F1E7DA` | Latar segmented control, garis pemisah dalam kartu |
| `cell` | `#FBF6EE` | Kotak angka kecil di dalam kartu, input di dalam kartu |
| `border` | `#E9DCCB` | Garis tepi kartu dan navigasi |
| `inputBorder` | `#DCCBB6` | Garis tepi input |
| `primary` | `#6B3E26` | Tombol utama, kartu hero, chip/segmen terpilih, tautan |
| `onPrimary` | `#FFF8EF` | Teks dan ikon di atas `primary` |
| `onPrimaryMuted` | `#E7D3BC` | Label sekunder di kartu hero |
| `primaryContainer` | `#F1E2CF` | Indikator tab aktif, lingkaran ikon, banner netral |
| `onPrimaryContainer` | `#5A3420` | Teks di atas `primaryContainer` (status Baru, Perkiraan) |
| `text` | `#2B1D14` | Teks utama |
| `textMuted` | `#6F5E52` | Keterangan, label input, ikon sekunder |
| `success` / `successContainer` | `#1F5C38` / `#DDF1E4` | Untung, Lengkap, Siap, Stok cukup |
| `warning` / `warningContainer` | `#7A4A00` / `#FFF0D4` | Menipis, Belum lengkap, Diproses, peringatan stok |
| `danger` / `dangerContainer` | `#9C2219` / `#FBE4E2` | Rugi, Terlambat, Belum bayar, rugi sisa |
| `dangerStrong` | `#B3261E` | Titik notifikasi, titik terlambat di kalender, bar bahan pembatas |
| `accentWarm` | `#B8865B` | Titik "ada pesanan" di kalender |
| `barNeutral` | `#C9A27E` | Bar kapasitas bahan yang bukan pembatas |
| `dashed` | `#B99572` | Garis putus-putus tombol "Tambah bahan/item" |

Kontras teks (WCAG AA minimal 4,5:1), dihitung dari nilai di atas:

| Pasangan | Rasio |
| --- | --- |
| `text` di `background` | 15,1:1 |
| `textMuted` di `background` / `surface` | 5,7:1 / 6,2:1 |
| `onPrimary` di `primary` | 8,5:1 |
| `onPrimaryMuted` di `primary` | 6,2:1 |
| `success` di `successContainer` | 6,7:1 |
| `warning` di `warningContainer` | 6,7:1 |
| `danger` di `dangerContainer` | 6,5:1 |
| `onPrimaryContainer` di `primaryContainer` | 8,5:1 |
| `primary` di `surface` (tautan, tombol outline) | 9,0:1 |

## 4. Tipografi

Dua keluarga huruf, keduanya berlisensi OFL dan **dibundel sebagai aset** (tidak diunduh saat runtime) supaya sama saat offline.

| Gaya | Huruf | Ukuran / tebal | Contoh |
| --- | --- | --- | --- |
| Judul layar (tab) | Fraunces | 28 / 600 | "Beranda", "Menu" |
| Judul layar (detail/form) | Fraunces | 24 / 600 | "Ubah resep", "Tutup hari" |
| Angka hero | Plus Jakarta Sans | 34–36 / 700 | "Rp82.950" |
| Angka besar | Plus Jakarta Sans | 20–22 / 700 | Total belanja, saran harga |
| Judul bagian | Plus Jakarta Sans | 16 / 700 | "Pesanan hari ini (2)" |
| Isi / nama item | Plus Jakarta Sans | 14–15 / 500–600 | "Bu Sari", "Tepung terigu" |
| Keterangan | Plus Jakarta Sans | 12–13 / 400–600 | "Sisa 300 g, batas minimum 400 g" |
| Label navigasi | Plus Jakarta Sans | 12 / 700 aktif, 500 tidak aktif | "Bahan" |

Semua angka memakai **angka tabular** (`FontFeature.tabularFigures()`) agar kolom Rupiah rata.

## 5. Jarak, bentuk, dan sentuhan

- **Margin layar:** 20. **Jarak antar bagian:** 20–24. **Jarak dalam kartu:** 8–14.
- **Radius:** kartu 16, kartu hero 20, input dan tombol kecil 12, tombol utama 14, chip 18, pill status 999 (penuh), bottom sheet 24 di sudut atas.
- **Bayangan:** tidak dipakai; kedalaman dari garis tepi `border` dan perbedaan latar.
- **Tinggi:** input 48, tombol utama 52, chip 36–40, navigasi bawah 72.
- **Target sentuh:** minimal 48 dp di Flutter (tombol ikon, stepper, chip diberi area sentuh 48 walau tampilannya lebih kecil).

## 6. Ikon

Garis (outlined), ketebalan setara 1,8–2 pada kanvas 24. Tidak memakai emoji. Padanan di `Icons` Flutter:

| Kegunaan | Ikon Flutter |
| --- | --- |
| Tab Beranda / Pesanan / Menu / Bahan / Laporan | `home_outlined` / `calendar_month_outlined` / `bakery_dining_outlined` / `inventory_2_outlined` / `bar_chart_outlined` |
| Pesanan baru / Penjualan / Belanja | `receipt_long_outlined` / `sell_outlined` / `shopping_cart_outlined` |
| Produksi / Pengeluaran / Tutup hari | `local_fire_department_outlined` / `account_balance_wallet_outlined` / `bedtime_outlined` |
| Notifikasi / Peringatan / Untung | `notifications_outlined` / `warning_amber_rounded` / `trending_up` |
| Kembali / Lanjut / Tambah / Kurang / Tutup / Hapus | `arrow_back` / `chevron_right` / `add` / `remove` / `close` / `delete_outline` |

## 7. Komponen

| Komponen | Spesifikasi | Dipakai di |
| --- | --- | --- |
| **Kartu hero** | Latar `primary`, radius 20, padding 18–20. Label kecil `onPrimaryMuted`, angka hero, pill status di kanan atas, grid 3 metrik dipisah garis `#8A5A40`, tautan "Lihat per menu ›" | Beranda, Detail menu, Bahan |
| **Kartu** | Latar `surface`, garis `border`, radius 16, padding 14–16 | Semua layar |
| **Kotak angka** | Latar `cell`, radius 10, label 12 `textMuted` di atas angka 15/600–700 | Grid 3 kolom di kartu menu dan laporan |
| **Pill status** | Tinggi ±24, padding 4×10, teks 12/700, warna pasangan status (bagian 8) | Pesanan, menu, bahan |
| **Chip pilihan** | Tinggi 36–40, radius 18. Terpilih: latar dan garis `primary`, teks `onPrimary`. Tidak terpilih: latar `surface`, garis `border` | Filter, channel, alasan dibuang, target produksi |
| **Segmented control** | Wadah `surfaceMuted` radius 12–14 padding 4; segmen terpilih putih 700, lainnya transparan `textMuted` | Periode laporan, markup/margin |
| **Stepper** | Tombol − dan + 44×44 radius 12 latar `cell`; angka 18/700 di tengah | Tutup hari, item pesanan |
| **Input** | Label 13/600 `textMuted` di atas; kotak tinggi 48, radius 12, garis `inputBorder`; isi 15–16 | Semua form |
| **Tombol utama** | Tinggi 52, radius 14, latar `primary`, teks 16/700, lebar penuh di bilah bawah putih bergaris atas | Akhir setiap form |
| **Tombol sekunder** | Outline `primary` atau `border`, latar putih | "Pakai harga ini", "Ubah resep" |
| **Tombol tambah** | Tinggi 48, garis putus-putus 1,5 `dashed`, teks `primary` 700 dengan ikon + | "Tambah bahan", "Tambah item" |
| **Baris rincian** | Label kiri (`textMuted`), nilai kanan, pemisah `surfaceMuted`; baris total 15/700 | Rincian HPP, laporan, ringkasan pesanan |
| **Bar kapasitas** | Tinggi 8 radius 4 di atas `surfaceMuted`; lebar = cukup-untuk-N-resep / 5; bahan pembatas `dangerStrong` + label "(pembatas)" tebal | Detail menu |
| **Kalender bulan** | Grid 7 kolom mulai Senin; sel 48 radius 12; terpilih latar `primary`; hari ini cincin 2 `primary`; titik 6 di bawah angka (`accentWarm` ada pesanan, `dangerStrong` terlambat) | Pesanan |
| **Kotak info** | Radius 10–12, padding 10×12, teks 13/600 dengan pasangan warna status | Peringatan stok, HPP belum lengkap, sukses |
| **Bottom sheet** | Latar `surface`, radius atas 24, pegangan 40×4, scrim `#2B1D14` 45% | Bahan baru dari form resep |
| **Navigasi bawah** | 5 tab, tinggi 72, latar putih garis atas `border`; tab aktif: pil 56×30 `primaryContainer` di belakang ikon, label `primary` 700 | Layar tab |

## 8. Status dan label

| Objek | Status → warna |
| --- | --- |
| Hari | **Untung** → success · **Rugi** → danger |
| HPP menu | **Lengkap** → success · **Perkiraan** → primaryContainer · **Belum lengkap** → warning |
| Bahan | **Menipis** → danger · **Belum ada harga** → warning |
| Pesanan | **Baru** → primaryContainer · **Diproses** → warning · **Siap** → success · **Selesai** → success · **Terlambat** → danger · **Dibatalkan** → teks `textMuted` dicoret |
| Pembayaran | **Belum bayar** → teks danger · **DP Rp…** → teks `textMuted` · **Lunas** → teks `textMuted` |
| Sisa produk | **Aman s.d. tanggal** → hijau lembut (`#2F5A2A` di `#EAF0E6`) · **Habis besok** → warning · **Lewat umur simpan** → danger |

## 9. Format angka, tanggal, dan teks

| Data | Format | Contoh |
| --- | --- | --- |
| Uang | `Rp` tanpa spasi, titik ribuan, tanpa desimal | Rp82.950 |
| Uang negatif | Tanda minus asli (U+2212) di depan | −Rp24.175 |
| Harga per satuan | Maksimal 2 desimal dengan koma, hanya jika perlu | Rp15/g, Rp93,85/g |
| Persen | 1 desimal dengan koma | 39,6% |
| Takaran | Titik ribuan, koma desimal, satuan setelah spasi | 1.000 g, 1,5 resep |
| Tanggal panjang | Hari, tanggal bulan tahun | Senin, 19 Oktober 2026 |
| Tanggal pendek | Tanggal + 3 huruf bulan | 19 Okt |
| Jam | 24 jam dengan titik | 16.00 |

Tombol memakai kata kerja ("Simpan belanja", "Tambah bahan"); judul memakai kata benda ("Pesanan baru"). Teks peringatan menyebut penyebab dan jalan keluarnya ("Stok brownies jadi 0 pcs. Catat produksi sebelum pesanan selesai").

## 10. Layar

| Layar | Artboard mockup | Isi utama | Aksi utama |
| --- | --- | --- | --- |
| Beranda | `Main` | Kartu hero laba bersih hari ini, Catat cepat (6 aksi), pesanan hari ini, Perlu perhatian | Ketuk aksi Catat cepat |
| Laporan harian | `Laporan` | Periode Hari/Minggu/Bulan, status + rincian sampai laba bersih, per menu, per channel, status Tutup hari | — |
| Tutup hari | `TutupHari` | Sisa per menu ready stock, stepper dibuang, alasan, rugi sisa dan nilai yang disimpan | Simpan Tutup hari |
| Daftar menu | `Menu` | Filter, kartu menu (HPP, harga, margin, kapasitas, tanda HPP) | Menu baru |
| Detail menu | `DetailMenu` | HPP hero, saran harga, rincian HPP, kapasitas + pembatas, simulasi target | Catat produksi |
| Ubah resep | `FormResep` | Nama, hasil, umur simpan, mode stok, takaran bahan, upah pemilik, HPP langsung; bottom sheet bahan baru | Simpan |
| Pesanan | `Pesanan` | Kalender bulan, daftar pesanan tanggal terpilih | + Pesanan |
| Pesanan baru | `FormPesanan` | Pelanggan, channel, item, jadwal, pembayaran, pengingat, ringkasan laba | Simpan pesanan |
| Bahan | `Bahan` | Nilai modal sisa bahan + stok menu jadi, filter, daftar bahan | + Belanja |
| Belanja bahan | `FormBelanja` | Tanggal, pemasok, item dengan harga per satuan dan perubahan harga rata-rata | Simpan belanja |

## 11. Alur utama

1. **Belanja bahan:** Beranda › Catat cepat "Belanja" › isi jumlah dan total harga per item › lihat harga rata-rata baru › Simpan belanja.
2. **Menu baru + resep:** Menu › Menu baru › isi resep › bahan belum ada? "Tambah bahan" › isi nama, satuan, stok awal atau harga › Simpan dan pakai › cek status HPP › Simpan.
3. **Pesanan:** Beranda › "Pesanan baru" › pilih channel › item › jadwal › DP › Simpan pesanan; pengingat terjadwal otomatis.
4. **Tutup hari:** notifikasi 20.00 atau Beranda › "Tutup hari" › isi jumlah dibuang dan alasannya › Simpan Tutup hari › Laporan menampilkan status hari ini.

## 12. Aksesibilitas

- Kontras semua pasangan teks ≥ 4,5:1 (bagian 3).
- Status tidak hanya dari warna; selalu ada teks.
- Tombol ikon punya label semantik (`Semantics`/`tooltip`), mis. "Kembali", "Tambah jumlah dibuang Brownies".
- Tampilan tetap utuh sampai skala huruf sistem 130%: teks boleh turun baris, tidak terpotong.
- Target sentuh minimal 48 dp.

## 13. Catatan implementasi Flutter

Warna inti ke `ColorScheme`, warna status ke `ThemeExtension` sendiri:

```dart
const cocoa = Color(0xFF6B3E26);

final theme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PlusJakartaSans',
  scaffoldBackgroundColor: const Color(0xFFFBF6EE),
  colorScheme: const ColorScheme.light(
    primary: cocoa,
    onPrimary: Color(0xFFFFF8EF),
    primaryContainer: Color(0xFFF1E2CF),
    onPrimaryContainer: Color(0xFF5A3420),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF2B1D14),
    onSurfaceVariant: Color(0xFF6F5E52),
    outline: Color(0xFFDCCBB6),
    outlineVariant: Color(0xFFE9DCCB),
    error: Color(0xFF9C2219),
    errorContainer: Color(0xFFFBE4E2),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    height: 72,
    backgroundColor: Color(0xFFFFFFFF),
    indicatorColor: Color(0xFFF1E2CF),
  ),
);
```

- Status (success, warning, danger beserta container-nya) dibuat sebagai `ThemeExtension<StatusColors>` agar widget pill dan kotak info mengambil dari satu tempat.
- Font: Plus Jakarta Sans (400, 500, 600, 700) dan Fraunces (600) sudah dibundel di `assets/fonts/` (TTF statis dari Google Fonts) dan didaftarkan di `pubspec.yaml` dengan nama keluarga `PlusJakartaSans` dan `Fraunces`. Lisensi OFL-nya ikut dibundel dan didaftarkan ke `LicenseRegistry` di `main.dart`. Jangan memakai paket yang mengunduh font saat runtime.
- Angka tabular: `TextStyle(fontFeatures: [FontFeature.tabularFigures()])` di gaya angka.
- Format Rupiah dan tanggal memakai `intl` dengan locale `id_ID`; pastikan hasilnya cocok dengan bagian 9 (tanpa spasi setelah "Rp").
- Tema ini sudah diterapkan di `lib/presentation/theme.dart` (`AppColors`, `StatusColors`, `buildAppTheme()`).

## 14. Belum didesain

Detail pesanan, kartu stok bahan, stok menu jadi, pengeluaran, pengaturan (termasuk channel dan upah per jam), onboarding, tampilan saat data kosong, dan mode gelap. MVP memakai tema terang saja.

Direncanakan di PRD tab "Rencana fase 2b": **token warna mode gelap** (sprint S8), didesain dan di-acc lewat mockup sebelum dikoding.

## 15. Gerak

Di-acc lewat mockup `Gerak` (21 Okt 2026). Kode: `lib/presentation/motion.dart`.

| Token | Durasi | Untuk |
| --- | --- | --- |
| `Motion.fast` | 150 ms | tekan tombol, sakelar, centang, segmented |
| `Motion.medium` | 250 ms | ganti tab, dialog, bottom sheet, angka berubah, kartu pembaruan muncul |
| `Motion.slow` | 300 ms | pindah layar, kartu → detail |

- Kurva: masuk `Easing.emphasizedDecelerate` (melambat di akhir), keluar `Easing.emphasizedAccelerate`, pindah posisi `Easing.standard`.
- Pindah layar: shared axis horizontal untuk semua rute (`AppPageTransitionsBuilder` di tema).
- Tab bawah: fade-through (`FadeThroughTabs`); isi lama memudar di 35% pertama, isi baru memudar masuk dengan skala 0,92 → 1. Semua tab tetap hidup, jadi posisi gulir dan tumpukan layar tiap tab tidak hilang.
- Kartu → detail: container transform (`ContainerToDetail`) untuk kartu menu, kartu pesanan, dan baris bahan. Deep link dari notifikasi tetap memakai rute biasa.
- Daftar: `StaggeredEntrance` 30 ms per item, hanya 8 item pertama, hanya saat item pertama kali dibuat.
- Angka: `AnimatedRupiah` untuk angka besar di Beranda dan nilai modal Bahan.
- Tekan: `Pressable` mengecilkan ke 0,97 (tombol bilah bawah, ubin Catat cepat).
- Getar (`Haptics`): ringan saat simpan berhasil, sedang sebelum aksi membatalkan atau keluar akun, klik halus untuk pilihan dan tab.
- Memuat: `SkeletonList` berdenyut pelan (opasitas 1 → 0,5, 1 detik) menggantikan lingkaran putar di daftar Menu, Pesanan, Bahan.
- Dialog: `showAppDialog` (skala 0,9 → 1 + pudar, 250 ms) menggantikan `showDialog`; snackbar mengambang di atas navigasi bawah.
- Pengaturan Android "hapus animasi" aktif → semua durasi 0 (`Motion.of`); getar tetap.
- Belum: animasi pratinjau gestur kembali prediktif Android 14+; gestur kembali tetap berfungsi seperti biasa.

## 16. Nota dan dokumen PDF

Dibuat langsung tanpa mockup atas pilihan pengguna (S3, 21 Okt 2026); dicek dari APK.

- Font PDF: Plus Jakarta Sans yang dibundel (Regular dan Bold), supaya Rp, ×, −, dan · tampil benar. Warna: teks `text`, keterangan `textMuted`, garis `inputBorder`, judul dan tanda LUNAS `primary`, kotak info pembayaran `primaryContainer`.
- Nota A6 (105 × 148 mm, margin 8 mm, teks 8,5 pt): kepala rata kiri (logo, nama, alamat, WhatsApp), nomor nota, jadwal, pelanggan, item (nama tebal, lalu "10 × Rp8.000" dan total rata kanan), ringkasan, Total tebal, LUNAS dalam kotak bergaris atau Sudah dibayar/Sisa, kotak Pembayaran (hanya bila belum lunas), catatan, catatan kaki di tengah.
- Struk 58 mm (margin 3 mm, teks 7 pt): isi sama, kepala di tengah, panjang halaman mengikuti isi.
- Laporan A4 (margin 16/14 mm, teks 9,5 pt): kepala logo + nama + periode, Ringkasan, tabel Per menu, Per channel, Pengeluaran dengan kepala tabel `primaryContainer` dan garis bawah tipis; nomor halaman di kaki.
- Teks nota WhatsApp: tebal dengan `*`, satu baris per item, baris kosong antar bagian.
- Lembar pilihan (Nota di Detail pesanan, Ekspor di Laporan): bottom sheet `background` dengan ListTile ikon garis; pilihan yang tidak bisa dipakai tampil nonaktif dengan alasannya.
- Pratinjau PDF: AppBar dengan tombol Bagikan dan Cetak, halaman di atas latar `surfaceMuted`.

## 17. Harga channel, riwayat HPP, simulasi, dan kas

Dibuat langsung tanpa mockup atas pilihan pengguna (S4 + S5, 21 Okt 2026); memakai komponen yang sudah ada.

- Detail menu, setelah Saran harga jual: kartu **Harga per channel** (baris: nama channel, harga atau "harga utama" abu-abu, keterangan "potongan RpX · laba RpY/pcs", chevron) lalu kartu **Riwayat HPP** (grafik garis `primary` tinggi 140 dp dengan titik kecil, lalu daftar perubahan: tanggal kecil abu-abu, "Rp4.835 → Rp5.120" tebal, sebab di bawahnya; naik = `danger`, turun = `success`).
- Dialog harga channel: `showAppDialog`, kolom Rupiah, teks saran di bawahnya, tombol Samakan dengan harga utama (teks), Batal, Simpan.
- Simulasi harga: layar penuh; Segmented Persen / Harga baru; daftar bahan terpilih sebagai kartu dengan kolom isian dan tombol hapus; tombol Tambah bahan (lembar cari); hasil sebagai kartu per menu: nama, "HPP Rp4.835 → Rp5.300 (+Rp465)", "Laba/pcs Rp3.165 → Rp2.700", "Saran harga Rp8.500"; InfoBox netral "Simulasi tidak menyimpan apa pun".
- Layar Kas: kartu hero total saldo (gaya `_StatusHero` Laporan), baris akun (nama, jenis, saldo); pemilih bulan seperti Laporan; ringkasan masuk/keluar/bersih; kartu penjelasan laba vs kas; daftar mutasi per hari (masuk `success`, keluar `danger`). Tombol bawah **Catat kas**; AppBar **Atur akun**.
- Lembar Catat kas: Segmented 4 jenis (Modal masuk, Ambil pribadi, Pindah, Koreksi saldo), ChoicePill akun (dan akun tujuan untuk Pindah), nominal, tanggal, catatan.
- Form Belanja dan Pengeluaran: baris ChoicePill "Dibayar dari" (akun aktif), bawaan Tunai.
