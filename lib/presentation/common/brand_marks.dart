import 'package:flutter/material.dart';

import '../theme.dart';

/// Ikon cupcake BuatUsaha (mockup `IkonSplash`), digambar dari path yang
/// sama dengan ikon aplikasi Android supaya tetap tajam di semua ukuran.
class CupcakeMark extends StatelessWidget {
  const CupcakeMark({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _PathsPainter(24, const [
      _Shape(
        'M7.2 13.2h9.6l-1.5 7.1a1 1 0 0 1-1 .8H9.7a1 1 0 0 1-1-.8z',
        AppColors.accentWarm,
      ),
      _Shape(
        'M10.4 13.6l.4 7.2M13.6 13.6l-.4 7.2',
        AppColors.primary,
        stroke: 0.7,
      ),
      _Shape(
        'M5.6 13.4a2.4 2.4 0 0 1 1.2-4.5A4.4 4.4 0 0 1 12 5.6'
        'a4.4 4.4 0 0 1 5.2 3.3 2.4 2.4 0 0 1 1.2 4.5z',
        AppColors.primary,
      ),
      _Shape(
        'M10.7 4.2a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0-2.6 0z',
        AppColors.dangerStrong,
      ),
    ]),
  );
}

/// Logo "G" Google untuk tombol Masuk dengan Google, sesuai panduan merek
/// Google Sign-In (empat warna resmi, tidak diubah).
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _PathsPainter(48, const [
      _Shape(
        'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
        '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
        Color(0xFFEA4335),
      ),
      _Shape(
        'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
        '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
        Color(0xFF4285F4),
      ),
      _Shape(
        'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19'
        'C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
        Color(0xFFFBBC05),
      ),
      _Shape(
        'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
        '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
        Color(0xFF34A853),
      ),
    ]),
  );
}

class _Shape {
  const _Shape(this.d, this.color, {this.stroke});

  final String d;
  final Color color;

  /// Tebal garis dalam satuan viewBox; `null` = diisi.
  final double? stroke;
}

class _PathsPainter extends CustomPainter {
  const _PathsPainter(this.viewBox, this.shapes);

  final double viewBox;
  final List<_Shape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / viewBox, size.height / viewBox);
    for (final s in shapes) {
      final paint = Paint()
        ..color = s.color
        ..isAntiAlias = true;
      if (s.stroke != null) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.stroke!
          ..strokeCap = StrokeCap.round;
      }
      canvas.drawPath(parseSvgPath(s.d), paint);
    }
  }

  @override
  bool shouldRepaint(_PathsPainter old) => false;
}

/// Pembaca data path SVG kecil (M L H V C S A Z, huruf besar dan kecil).
Path parseSvgPath(String d) {
  final tokens = RegExp(
    r'[MmLlHhVvCcSsAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  double? lastCx, lastCy;
  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    final before = i;
    if (isCommand(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + next();
        y = oy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Pasangan berikutnya setelah M adalah L.
        cmd = rel ? 'l' : 'L';
        lastCx = null;
      case 'L':
        x = ox + next();
        y = oy + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'H':
        x = (rel ? x : 0.0) + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'V':
        y = (rel ? y : 0.0) + next();
        path.lineTo(x, y);
        lastCx = null;
      case 'C':
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'S':
        final x1 = lastCx == null ? x : 2 * x - lastCx;
        final y1 = lastCy == null ? y : 2 * y - lastCy;
        final x2 = ox + next(), y2 = oy + next();
        x = ox + next();
        y = oy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCx = x2;
        lastCy = y2;
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final large = next() != 0, sweep = next() != 0;
        x = ox + next();
        y = oy + next();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: large,
          clockwise: sweep,
        );
        lastCx = null;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        lastCx = null;
    }
    // Angka sisa setelah Z atau perintah tak dikenal: dilewati.
    if (i == before) i++;
  }
  return path;
}
