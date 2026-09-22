import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Rect;

// The same conditional-import shape browser_intake_web.dart beside it
// already uses: this file only ever compiles for the browser.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/recognized_text.dart';

/// Page text recognition in a browser: Tesseract, compiled to WebAssembly,
/// running in a worker on this machine.
///
/// **Why an OCR engine at all.** Hiding a student's name needs two things:
/// finding the line that says `Name:`, and knowing what pixels to paint.
/// The label is printed — it is part of the test template — so this is a
/// printed-text problem with bounding boxes, not a handwriting problem.
/// Tesseract is good at exactly that.
///
/// **Why not the browser's own text detector.** `TextDetector` (the Shape
/// Detection API) would be free and fast, and it exists in Chrome on some
/// platforms and nowhere else. Shipping it as the implementation would mean
/// the privacy promise silently held for some teachers and silently did not
/// for others, with nothing on screen telling them which they were. One
/// engine that behaves the same in every browser is worth its download.
///
/// **Why it is served from here.** Same reason pdf.js is (see web/index.html):
/// schools block CDNs, and a third-party script that parses a page of a
/// child's work is a dependency worth not having. Engine, worker and the
/// English model are all vendored under `web/tesseract/`.
///
/// **Why it loads late.** It is about 7 MB. A teacher who only ever imports
/// a Google Form must not pay for that on app open, so nothing is fetched
/// until a page of student work is actually on its way in. [warmUp] starts
/// it at the upload gate, well before the teacher taps Mark.
///
/// **How it is spoken to.** `window.postMessage`, not JS interop: the
/// structured clone carries the page bytes across and brings back one JSON
/// string, so the whole boundary is two message shapes and this file stays
/// analysable from a phone build.
class PageTextReader {
  /// Everything it needs ships with the app.
  static bool get available => true;

  /// It reads the printed label. It does not read the child's handwriting,
  /// and the app is not allowed to pretend otherwise.
  static OcrTrust get trust => OcrTrust.printedLabelsOnly;

  static const _channel = 'markless.ocr';

  static final ValueNotifier<bool> _preparing = ValueNotifier<bool>(false);

  /// True while the engine is downloading. Worth saying out loud: it is a
  /// once-per-browser pause of a few seconds, not a stuck app.
  static ValueListenable<bool> get preparing => _preparing;

  static Future<bool>? _loading;
  static var _nextId = 0;

  /// Fetches the engine if it is not here yet. Safe to call repeatedly and
  /// safe to ignore the result — a failure here just means no name gets
  /// hidden on this page, which the app already knows how to report.
  static Future<bool> warmUp() => _loading ??= _load();

  static Future<bool> _load() async {
    _preparing.value = true;
    try {
      final script = html.ScriptElement()..src = 'tesseract/markless_ocr.js';
      final ready = script.onLoad.first;
      final failed = script.onError.first.then<html.Event>(
        (_) => throw StateError('tesseract/markless_ocr.js did not load'),
      );
      html.document.head!.append(script);
      await Future.any(<Future<html.Event>>[ready, failed]).timeout(const Duration(seconds: 30));

      final reply = await _ask(const {'op': 'load'}, const Duration(minutes: 3));
      if (reply['ok'] != true) throw StateError('the page reader did not start: ${reply['error']}');
      return true;
    } catch (e) {
      debugPrint('PageTextReader.warmUp failed: $e');
      // Let a later page try again — a flaky first fetch should not disable
      // name hiding for the rest of the session.
      _loading = null;
      return false;
    } finally {
      _preparing.value = false;
    }
  }

  /// Reads the page, or hands back nothing.
  ///
  /// Nothing is the honest answer whenever the engine did not load, the
  /// image did not decode, or the reading was too weak to act on. The
  /// caller treats an empty list as "no name was hidden here" and says so.
  static Future<List<RecognizedWord>> read(Uint8List bytes) async {
    try {
      if (!await warmUp()) return const [];
      final reply = await _ask({'op': 'read', 'bytes': bytes}, const Duration(minutes: 2));
      final json = reply['json'];
      if (json is! String) return const [];
      return believableWords(_parse(json));
    } catch (e) {
      debugPrint('PageTextReader.read failed: $e');
      return const [];
    }
  }

  /// One request, one reply, over the window's own message channel.
  static Future<Map<Object?, Object?>> _ask(Map<String, Object?> request, Duration timeout) {
    final id = 'ocr-${_nextId++}';
    final done = Completer<Map<Object?, Object?>>();
    late StreamSubscription<html.MessageEvent> sub;
    sub = html.window.onMessage.listen((e) {
      final data = e.data;
      if (data is! Map) return;
      if (data['channel'] != _channel || data['dir'] != 'reply' || data['id'] != id) return;
      sub.cancel();
      if (!done.isCompleted) done.complete(data);
    });
    html.window.postMessage(
      <String, Object?>{...request, 'channel': _channel, 'dir': 'ask', 'id': id},
      html.window.location.origin,
    );
    return done.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      throw TimeoutException('the page reader did not answer', timeout);
    });
  }

  /// The glue hands back a JSON string rather than an object graph: one
  /// boundary, one shape, and nothing to keep in step on either side.
  static List<OcrReading> _parse(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const [];
    final words = decoded['words'];
    if (words is! List) return const [];
    final out = <OcrReading>[];
    for (final w in words) {
      if (w is! Map) continue;
      final text = w['t'];
      if (text is! String) continue;
      final x0 = _num(w['x0']), y0 = _num(w['y0']), x1 = _num(w['x1']), y1 = _num(w['y1']);
      if (x0 == null || y0 == null || x1 == null || y1 == null) continue;
      out.add(OcrReading(
        text: text,
        rect: Rect.fromLTRB(x0, y0, x1, y1),
        lineId: _num(w['l'])?.round() ?? 0,
        confidence: _num(w['c']) ?? 0,
      ));
    }
    return out;
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;
}
