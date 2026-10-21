import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/local_notifications.dart';
import '../services/sync_controller.dart';
import '../services/update_controller.dart';
import 'auth/login_screen.dart';
import 'auth/prepare_screen.dart';
import 'common/brand_marks.dart';
import 'home/home_screen.dart';
import 'motion.dart';
import 'menu/menu_detail_screen.dart';
import 'menu/menu_form_screen.dart';
import 'menu/menu_screen.dart';
import 'orders/cost_correction_screen.dart';
import 'orders/order_detail_screen.dart';
import 'orders/order_form_screen.dart';
import 'orders/orders_screen.dart';
import 'reports/day_close_screen.dart';
import 'reports/expenses_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/about_screen.dart';
import 'settings/onboarding_screen.dart';
import 'settings/settings_screen.dart';
import 'stock/ingredient_detail_screen.dart';
import 'stock/ingredient_form_screen.dart';
import 'stock/ingredients_screen.dart';
import 'stock/purchase_form_screen.dart';
import 'theme.dart';

class AppTab {
  const AppTab(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;
}

/// Lima tab navigasi bawah (PRD bagian 7, Design.md bagian 6).
const appTabs = [
  AppTab('/beranda', 'Beranda', Icons.home_outlined),
  AppTab('/pesanan', 'Pesanan', Icons.calendar_month_outlined),
  AppTab('/menu', 'Menu', Icons.bakery_dining_outlined),
  AppTab('/bahan', 'Bahan', Icons.inventory_2_outlined),
  AppTab('/laporan', 'Laporan', Icons.bar_chart_outlined),
];

GoRouter buildRouter({Listenable? refresh, GoRouterRedirect? redirect}) {
  // Form dan detail tampil penuh di atas navigasi bawah.
  final rootKey = GlobalKey<NavigatorState>();

  GoRoute tabRoute(AppTab tab) => switch (tab.path) {
    '/pesanan' => GoRoute(
      path: tab.path,
      builder: (context, state) => const OrdersScreen(),
      routes: [
        GoRoute(
          path: 'baru',
          parentNavigatorKey: rootKey,
          builder: (context, state) => OrderFormScreen(
            initialDay: DateTime.tryParse(
              state.uri.queryParameters['tanggal'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: 'jual',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const OrderFormScreen(direct: true),
        ),
        GoRoute(
          path: 'koreksi-hpp',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const CostCorrectionScreen(),
        ),
        GoRoute(
          path: ':id',
          parentNavigatorKey: rootKey,
          builder: (context, state) =>
              OrderDetailScreen(id: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'ubah',
              parentNavigatorKey: rootKey,
              builder: (context, state) =>
                  OrderFormScreen(id: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
    '/menu' => GoRoute(
      path: tab.path,
      builder: (context, state) => const MenuScreen(),
      routes: [
        GoRoute(
          path: 'baru',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const MenuFormScreen(),
        ),
        GoRoute(
          path: ':id',
          parentNavigatorKey: rootKey,
          builder: (context, state) =>
              MenuDetailScreen(id: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'ubah',
              parentNavigatorKey: rootKey,
              builder: (context, state) =>
                  MenuFormScreen(id: state.pathParameters['id']),
            ),
          ],
        ),
      ],
    ),
    '/bahan' => GoRoute(
      path: tab.path,
      builder: (context, state) => const IngredientsScreen(),
      routes: [
        GoRoute(
          path: 'baru',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const IngredientFormScreen(),
        ),
        GoRoute(
          path: 'belanja',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const PurchaseFormScreen(),
          routes: [
            GoRoute(
              path: ':purchaseId',
              parentNavigatorKey: rootKey,
              builder: (context, state) => PurchaseFormScreen(
                purchaseId: state.pathParameters['purchaseId'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: ':id',
          parentNavigatorKey: rootKey,
          builder: (context, state) =>
              IngredientDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    '/laporan' => GoRoute(
      path: tab.path,
      builder: (context, state) => const ReportsScreen(),
      routes: [
        GoRoute(
          path: 'pengeluaran',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const ExpensesScreen(),
        ),
      ],
    ),
    _ => GoRoute(
      path: tab.path,
      builder: (context, state) => const HomeScreen(),
    ),
  };

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: appTabs.first.path,
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(path: '/mulai', builder: (context, state) => const _Splash()),
      GoRoute(path: '/masuk', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/menyiapkan',
        builder: (context, state) => const PrepareScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => HomeShell(shell: shell),
        // Ganti tab dengan fade-through; semua tab tetap hidup (FR-11.7).
        navigatorContainerBuilder: (context, shell, children) =>
            FadeThroughTabs(index: shell.currentIndex, children: children),
        branches: [
          for (final tab in appTabs)
            StatefulShellBranch(routes: [tabRoute(tab)]),
        ],
      ),
      GoRoute(
        path: '/tutup-hari',
        builder: (context, state) => const DayCloseScreen(),
      ),
      GoRoute(
        path: '/pengaturan',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/tentang',
        builder: (context, state) => const AboutScreen(),
      ),
    ],
  );
}

/// Gerbang masuk wajib (FR-10.1, FR-10.13): status belum diketahui →
/// layar pembuka; belum masuk → layar Masuk; data belum terhubung → layar
/// Menyiapkan. Lokasi tujuan awal (mis. dari notifikasi) dibawa lewat
/// layar pembuka.
String? accountGate(SyncStatus status, GoRouterState state) {
  final at = state.matchedLocation;
  if (!status.ready) {
    if (at == '/mulai') return null;
    return Uri(
      path: '/mulai',
      queryParameters: {'ke': state.uri.toString()},
    ).toString();
  }
  if (status.user == null) return at == '/masuk' ? null : '/masuk';
  if (!status.linked) return at == '/menyiapkan' ? null : '/menyiapkan';
  // Layar Menyiapkan tetap tampil sampai "Mulai pakai" diketuk.
  if (at == '/mulai') return state.uri.queryParameters['ke'] ?? '/beranda';
  if (at == '/masuk') return '/beranda';
  return null;
}

class HppApp extends ConsumerStatefulWidget {
  const HppApp({super.key});

  @override
  ConsumerState<HppApp> createState() => _HppAppState();
}

class _HppAppState extends ConsumerState<HppApp> {
  final _refresh = ValueNotifier(0);
  late final GoRouter _router = buildRouter(
    refresh: _refresh,
    redirect: (context, state) =>
        accountGate(ref.read(syncControllerProvider), state),
  );
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    ref.listenManual(syncControllerProvider, (previous, next) {
      if (previous?.ready != next.ready ||
          previous?.user?.uid != next.user?.uid ||
          previous?.linked != next.linked) {
        _refresh.value++;
      }
    });
    // Ketuk notifikasi membuka layar terkait (FR-6.5).
    _taps = LocalNotifications.instance.taps.listen(_open);
    final launch = LocalNotifications.instance.launchPayload;
    if (launch != null) {
      LocalNotifications.instance.launchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(launch));
    }
  }

  void _open(String payload) {
    final (kind, id) = switch (payload.split(':')) {
      [final k, final v] => (k, v),
      [final k] => (k, ''),
      _ => ('', ''),
    };
    switch (kind) {
      case 'order':
        _router.push('/pesanan/');
      case 'ingredient':
        _router.push('/bahan/');
      case 'day-close':
        _router.push('/tutup-hari');
      case 'update':
        // Versi baru (FR-11.4): Beranda membuka dialog pembaruan.
        _router.go('/beranda');
        ref.read(updateControllerProvider.notifier).requestDialog();
      default:
        _router.go('/beranda');
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BuatUsaha',
      theme: buildAppTheme(),
      locale: const Locale('id'),
      supportedLocales: const [Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
    );
  }
}

/// Sama dengan layar pembuka Android, selama status akun dibaca.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 160,
          height: 160,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
          ),
          child: const CupcakeMark(size: 112),
        ),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (index) {
            Haptics.select();
            shell.goBranch(index, initialLocation: index == shell.currentIndex);
          },
          destinations: [
            for (final tab in appTabs)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}
