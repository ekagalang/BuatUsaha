import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../services/local_notifications.dart';
import 'home/home_screen.dart';
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

GoRouter buildRouter() {
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
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
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
    ],
  );
}

class HppApp extends StatefulWidget {
  const HppApp({super.key});

  @override
  State<HppApp> createState() => _HppAppState();
}

class _HppAppState extends State<HppApp> {
  final _router = buildRouter();
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
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
      default:
        _router.go('/beranda');
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HPP Usaha',
      theme: buildAppTheme(),
      locale: const Locale('id'),
      supportedLocales: const [Locale('id')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
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
          onDestinationSelected: (index) => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          destinations: [
            for (final tab in appTabs)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
          ],
        ),
      ),
    );
  }
}
