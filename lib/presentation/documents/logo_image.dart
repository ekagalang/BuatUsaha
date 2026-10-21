import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const logoMaxSide = 256;
const logoMaxBytes = 100 * 1024;

/// Logo usaha diperkecil ke sisi terpanjang 256 px, latar transparan jadi
/// putih, JPEG ≤ 100 KB dalam base64 (PRD S3); `null` = bukan gambar.
/// Berat untuk foto besar, jadi panggil lewat `Isolate.run`.
String? encodeLogo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = decoded;
  if (math.max(image.width, image.height) > logoMaxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: logoMaxSide)
        : img.copyResize(image, height: logoMaxSide);
  }
  final flat = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, image);
  for (var quality = 85; ; quality -= 15) {
    final jpg = img.encodeJpg(flat, quality: quality);
    if (jpg.length <= logoMaxBytes || quality <= 25) return base64Encode(jpg);
  }
}
