import 'package:qr/qr.dart';

/// A QR code as a small SVG (black squares on white, with the usual quiet zone).
String qrSvg(String data) {
  final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
  final img = QrImage(code);
  final n = img.moduleCount;
  const q = 4;
  final size = n + 2 * q;
  final sb = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" shape-rendering="crispEdges">')
    ..write('<rect width="$size" height="$size" fill="#ffffff"/>')
    ..write('<path fill="#000000" d="');
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (img.isDark(r, c)) sb.write('M${c + q} ${r + q}h1v1h-1z');
    }
  }
  sb.write('"/></svg>');
  return sb.toString();
}
