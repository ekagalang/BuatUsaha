import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/product_repository.dart';
import '../../services/local_notifications.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../theme.dart';

/// Onboarding 3 langkah: profil usaha → izin notifikasi → menu pertama
/// (FR-8.4).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _wage = TextEditingController();
  var _step = 0;
  var _busy = false;
  bool? _notifAllowed;
  bool? _exactAllowed;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _wage.dispose();
    super.dispose();
  }

  Future<String> _businessId() async =>
      (await ref.read(currentBusinessProvider.future)).id;

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    final id = await _businessId();
    final repo = ref.read(businessRepositoryProvider);
    await repo.updateBusiness(
      id,
      BusinessesCompanion(
        name: Value(
          _name.text.trim().isEmpty ? 'Usaha saya' : _name.text.trim(),
        ),
        phoneWa: Value(_phone.text.trim().isEmpty ? null : _phone.text.trim()),
      ),
    );
    final wage = parseRupiahInput(_wage.text);
    if (wage != null) await repo.setOwnerHourlyWage(id, wage);
    if (mounted) {
      setState(() {
        _busy = false;
        _step = 1;
      });
    }
  }

  Future<void> _askPermissions() async {
    final allowed = await LocalNotifications.instance.requestPermission();
    var exact = await LocalNotifications.instance.canScheduleExact();
    if (!exact) {
      await LocalNotifications.instance.requestExactAlarms();
      exact = await LocalNotifications.instance.canScheduleExact();
    }
    if (mounted) {
      setState(() {
        _notifAllowed = allowed;
        _exactAllowed = exact;
      });
    }
  }

  Future<void> _finish({String? goTo}) async {
    final id = await _businessId();
    await ref
        .read(businessRepositoryProvider)
        .updateBusiness(
          id,
          BusinessesCompanion(onboardedAt: Value(DateTime.now().toUtc())),
        );
    if (!mounted) return;
    context.go('/beranda');
    if (goTo != null) await context.push(goTo);
  }

  /// Contoh resep brownies dari PRD bagian 6, dengan harga perkiraan yang
  /// bisa diganti lewat belanja.
  Future<void> _sample() async {
    setState(() => _busy = true);
    final id = await _businessId();
    final stock = ref.read(stockRepositoryProvider);
    Future<String> ingredient(String name, BaseUnit unit, int price) async =>
        (await stock.createIngredient(
          businessId: id,
          name: name,
          baseUnit: unit,
          estimatedUnitCost: Decimal.fromInt(price),
        )).id;
    final recipe = [
      (await ingredient('Tepung terigu', BaseUnit.g, 14), '250'),
      (await ingredient('Gula pasir', BaseUnit.g, 16), '200'),
      (await ingredient('Telur', BaseUnit.pcs, 2000), '4'),
      (await ingredient('Cokelat batang', BaseUnit.g, 90), '200'),
      (await ingredient('Mentega', BaseUnit.g, 60), '150'),
      (await ingredient('Box kemasan', BaseUnit.pcs, 1500), '20'),
    ];
    final product = await ref
        .read(productRepositoryProvider)
        .createProduct(
          id,
          ProductInput(
            name: 'Brownies',
            sellingPrice: 8000,
            yieldQty: Decimal.fromInt(20),
            shelfLifeDays: 3,
            recipe: [
              for (final (ingredientId, qty) in recipe)
                RecipeInput(
                  ingredientId: ingredientId,
                  qtyBase: Decimal.parse(qty),
                ),
            ],
            costs: [
              const CostInput(
                name: 'Gas dan listrik',
                costType: CostType.utilities,
                basis: CostBasis.perBatch,
                amount: 5000,
              ),
              CostInput(
                name: 'Upah pemilik',
                costType: CostType.labor,
                basis: CostBasis.perBatch,
                laborHours: Decimal.fromInt(2),
              ),
            ],
          ),
        );
    await _finish(goTo: '/menu/$product/ubah');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? AppColors.primary
                              : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_step) {
                    0 => _profile(),
                    1 => _permissions(),
                    _ => _firstMenu(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 20),
    ],
  );

  Widget _profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        'Selamat datang',
        'Hitung HPP, catat stok, pesanan, dan untung-rugi harian usahamu. '
            'Semua data tersimpan di HP ini.',
      ),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nama usaha',
          hintText: 'mis. Dapur Bu Rina',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'No. WhatsApp (opsional)'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _wage,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Upah kerjamu per jam (opsional)',
          prefixText: 'Rp ',
          helperText: 'Dimasukkan ke HPP lewat jam kerja per resep.',
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy ? null : _saveProfile,
        child: const Text('Lanjut'),
      ),
    ],
  );

  Widget _permissions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        'Pengingat pesanan',
        'Aplikasi mengingatkan H-1 dan 2 jam sebelum jadwal ambil/kirim, '
            'ringkasan pagi, stok menipis, dan Tutup hari. Semuanya notifikasi '
            'lokal, tetap muncul tanpa internet.',
      ),
      if (_notifAllowed == false)
        const InfoBox(
          'Izin notifikasi ditolak. Bisa diizinkan nanti di Pengaturan.',
          kind: StatusKind.danger,
        ),
      if (_exactAllowed == false) ...[
        const SizedBox(height: 8),
        const InfoBox(
          'Alarm tepat belum diizinkan: pengingat bisa tertunda beberapa '
          'menit.',
        ),
      ],
      if (_notifAllowed == true && _exactAllowed == true)
        const InfoBox(
          'Notifikasi dan alarm tepat sudah diizinkan.',
          kind: StatusKind.success,
        ),
      const SizedBox(height: 16),
      if (_notifAllowed == null)
        FilledButton(
          onPressed: _askPermissions,
          child: const Text('Izinkan notifikasi'),
        )
      else
        FilledButton(
          onPressed: () => setState(() => _step = 2),
          child: const Text('Lanjut'),
        ),
      TextButton(
        onPressed: () => setState(() => _step = 2),
        child: const Text('Nanti saja'),
      ),
    ],
  );

  Widget _firstMenu() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        'Menu pertama',
        'Isi resep sekali, lalu HPP, saran harga, dan "bisa jadi berapa pcs" '
            'dihitung otomatis. Bahan yang belum ada bisa ditambah langsung '
            'dari form resep.',
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _sample,
        icon: const Icon(Icons.bakery_dining_outlined),
        label: const Text('Mulai dari contoh brownies'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Contoh berisi 6 bahan dengan harga perkiraan; ubah takaran dan '
        'harganya sesuai punyamu.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: _busy ? null : () => _finish(goTo: '/menu/baru'),
        child: const Text('Buat menu sendiri'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _finish(),
        child: const Text('Lewati, ke Beranda'),
      ),
    ],
  );
}
