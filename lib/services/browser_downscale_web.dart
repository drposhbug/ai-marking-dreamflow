import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Shrinks a photo to [maxSide] on the long side with the browser's own
/// decoder, before any Dart image code sees it.
///
/// In a browser there are no background isolates: package:image runs on the
/// page's only thread, and decoding a 12-megapixel phone photo there froze
/// the site for several seconds per upload. The browser's decoder is native
/// and applies the EXIF rotation itself. Returns null (use the original)
/// when the photo is already small or the browser can't do it.
Future<Uint8List?> browserDownscale(Uint8List bytes, {int maxSide = 1600}) async {
  try {
    final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS);
    final bitmap = await web.window.createImageBitmap(blob).toDart;
    final scale = maxSide / math.max(bitmap.width, bitmap.height);
    if (scale >= 1) {
      bitmap.close();
      return null;
    }
    final w = (bitmap.width * scale).round(), h = (bitmap.height * scale).round();
    final canvas = web.OffscreenCanvas(w, h);
    (canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D).drawImage(bitmap, 0, 0, w, h);
    bitmap.close();
    final out = await canvas.convertToBlob(web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.92)).toDart;
    return (await out.arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    return null;
  }
}
