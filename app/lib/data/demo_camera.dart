import 'dart:math';
import 'dart:typed_data';

/// Image de caméra simulée (mode démo) : BMP 24 bits généré à la volée, lisible
/// partout sans bibliothèque. Une entrée au soleil, une silhouette qui passe.
Uint8List demoCameraFrame(DateTime t, {int width = 320, int height = 180}) {
  final rowSize = (width * 3 + 3) & ~3;
  final dataSize = rowSize * height;
  final b = ByteData(54 + dataSize);
  b
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, 54 + dataSize, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little) // lignes de bas en haut
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, dataSize, Endian.little);

  final ms = t.millisecondsSinceEpoch;
  final walker = (ms / 40) % (width + 60) - 30;
  final sway = sin(ms / 900) * 3;
  final bytes = b.buffer.asUint8List();
  for (var y = 0; y < height; y++) {
    final row = 54 + (height - 1 - y) * rowSize;
    for (var x = 0; x < width; x++) {
      double r, g, bl;
      if (y < height * .55) {
        // Mur ensoleillé et porte d'entrée
        r = 246 - y * .45;
        g = 196 - y * .55;
        bl = 132 - y * .35;
        if (x > width * .58 && x < width * .74 && y > height * .12) {
          r = 116;
          g = 74;
          bl = 46;
        }
      } else {
        // Sol carrelé
        final tile = ((x ~/ 22) + (y ~/ 10)).isEven ? 8 : 0;
        r = 150 - (y - height * .55) * .5 + tile;
        g = 128 - (y - height * .55) * .45 + tile;
        bl = 104 - (y - height * .55) * .3 + tile;
      }
      // Ombre d'un palmier qui bouge doucement
      if ((x - 60 - sway - (height - y) * .25).abs() < 2 && y > height * .1) {
        r *= .7;
        g *= .7;
        bl *= .7;
      }
      // Silhouette
      final head = (x - walker) * (x - walker) + (y - height * .36) * (y - height * .36) < 64;
      final body = (x - walker).abs() < 9 && y > height * .41 && y < height * .82;
      if (head || body) {
        r = 52;
        g = 44;
        bl = 40;
      }
      final o = row + x * 3;
      bytes[o] = bl.clamp(0, 255).round();
      bytes[o + 1] = g.clamp(0, 255).round();
      bytes[o + 2] = r.clamp(0, 255).round();
    }
  }
  return bytes;
}
