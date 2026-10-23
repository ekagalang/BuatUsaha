import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ukuran layar uji dalam dp. MediaQuery membaca ukuran view, jadi
/// `setSurfaceSize` saja membuat aplikasi mengira lebarnya 800 (tablet).
void setScreenSize(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}
