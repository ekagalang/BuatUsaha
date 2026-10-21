import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buat_usaha/presentation/motion.dart';
import 'package:buat_usaha/presentation/theme.dart';

class _Counter extends StatefulWidget {
  const _Counter(this.label);

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => _n++),
    child: Text('${widget.label} $_n'),
  );
}

void main() {
  Widget app(Widget child, {bool reduce = false}) => MaterialApp(
    theme: buildAppTheme(),
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: c!,
    ),
    home: Scaffold(body: child),
  );

  testWidgets('ganti tab: isi tab lama tetap hidup dan animasi selesai', (
    tester,
  ) async {
    Widget tabs(int index) => app(
      FadeThroughTabs(
        index: index,
        children: const [_Counter('Beranda'), _Counter('Menu')],
      ),
    );
    await tester.pumpWidget(tabs(0));
    await tester.tap(find.text('Beranda 0'));
    await tester.pump();
    expect(find.text('Beranda 1'), findsOneWidget);

    await tester.pumpWidget(tabs(1));
    await tester.pump(const Duration(milliseconds: 100));
    // Di tengah transisi kedua tab tampil (lama memudar, baru masuk).
    expect(find.text('Menu 0'), findsOneWidget);
    await tester.pump(Motion.medium);
    expect(find.text('Beranda 1', skipOffstage: false), findsOneWidget);
    expect(find.text('Beranda 1'), findsNothing);

    await tester.pumpWidget(tabs(0));
    await tester.pump(Motion.medium);
    expect(find.text('Beranda 1'), findsOneWidget);
  });

  testWidgets('kartu membesar menjadi layar detail lalu kembali', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Center(
          child: ContainerToDetail(
            closed: (context, open) => InkWell(
              onTap: open,
              child: const SizedBox(
                width: 200,
                height: 80,
                child: Text('Kartu Brownies'),
              ),
            ),
            open: (context) =>
                Scaffold(appBar: AppBar(title: const Text('Detail Brownies'))),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Kartu Brownies'));
    await tester.pump();
    await tester.pump(Motion.slow);
    expect(find.text('Detail Brownies'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(Motion.slow);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Detail Brownies'), findsNothing);
    expect(find.text('Kartu Brownies'), findsOneWidget);
  });

  testWidgets('angka Rupiah berhitung sampai nilai baru', (tester) async {
    await tester.pumpWidget(app(const AnimatedRupiah(10000)));
    expect(find.text('Rp10.000'), findsOneWidget);
    await tester.pumpWidget(app(const AnimatedRupiah(26000)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Rp26.000'), findsNothing);
    await tester.pump(Motion.medium);
    expect(find.text('Rp26.000'), findsOneWidget);
  });

  testWidgets('"hapus animasi" di HP: dialog dan angka langsung tampil', (
    tester,
  ) async {
    await tester.pumpWidget(app(const AnimatedRupiah(10000), reduce: true));
    await tester.pumpWidget(app(const AnimatedRupiah(26000), reduce: true));
    await tester.pump();
    expect(find.text('Rp26.000'), findsOneWidget);

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(title: Text('Dialog')),
            ),
            child: const Text('Buka'),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.tap(find.text('Buka'));
    await tester.pump();
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('Dialog'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
  });
}
