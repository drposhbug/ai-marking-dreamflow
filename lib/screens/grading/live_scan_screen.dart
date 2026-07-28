import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/app/app_state.dart' show ScannedPage;
import 'package:marking_prokect_v2/services/document_processor.dart';

/// A live "CamScanner-style" auto-capture screen.
///
/// Holds the camera preview open continuously. When the frame goes
/// still (teacher has placed/held a page steady) for [_stillDuration],
/// it auto-captures, adds the page to the strip at the bottom, then
/// re-arms itself — waiting for motion (the page being swapped) before
/// it will fire again. The teacher keeps sliding pages under the camera
/// until they tap Done, which returns every captured page at once.
///
/// Pops with a `List<ScannedPage>` — empty list means cancelled.
class LiveScanScreen extends StatefulWidget {
  /// When true, closes and returns as soon as one page is captured
  /// (used to retake a single page from the grading setup screen).
  final bool singleShot;

  const LiveScanScreen({super.key, this.singleShot = false});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

enum _ScanState { idle, waitingForStillness, capturing, cooldown }

enum _DistanceHint { ok, tooFar, tooClose }

class _LiveScanScreenState extends State<LiveScanScreen> {
  CameraController? _controller;
  bool _ready = false;
  String? _error;

  _ScanState _state = _ScanState.idle;
  DateTime? _stillSince;
  Float64List? _lastBlocks;
  Float64List? _lastCaptureBlocks;
  _PageThumb? _lastAcceptedThumb;
  final List<ScannedPage> _pages = [];
  bool _webFallback = false;
  bool _flash = false;
  bool _noPaper = false;
  bool _samePage = false;
  bool _dupSkipped = false;
  bool _notAPage = false;
  bool _processing = false;
  bool _cutOff = false;
  _DistanceHint _hint = _DistanceHint.ok;

  // Motion detection: the frame is split into a grid of blocks and each
  // block's average brightness is compared against the previous frame.
  // A hand or page moving through part of the frame lights up the blocks
  // it crosses even when the whole-frame average barely changes.
  static const int _blocksX = 8;
  static const int _blocksY = 6;
  static const double _motionThreshold = 1.6; // mean per-block luma delta
  // How different the scene must look from the previously captured page
  // before another auto-capture is allowed — stops re-shooting the same
  // paper when a hand briefly enters the frame and leaves again.
  static const double _duplicateThreshold = 2.0;
  // Content-level duplicate check: each captured photo is compared against
  // the last saved page (correlation over a small translation search, so a
  // nudged paper still matches). At or above this, the shot is discarded.
  static const double _duplicateNcc = 0.82;
  static const Duration _stillDuration = Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final backCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCam,
        // 1080p — sharper text for the AI marker without huge uploads.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _ready = true;
        _webFallback = kIsWeb;
      });

      // camera_web does not support startImageStream() in any browser —
      // auto stillness-detection only works on a real native build.
      if (kIsWeb) return;

      await controller.startImageStream(_onFrame);
    } catch (e) {
      setState(() => _error = 'Could not start camera: $e');
    }
  }

  double _lastTextScore = 0;
  double _lastChromaScore = 0;

  /// Mean chroma (color-ness) of the center of the frame, from the camera's
  /// U/V planes. Paper is white → near zero; a wooden desk, carpet, or lap
  /// is strongly colored → high. Cheap and immune to auto-exposure tricks.
  void _sampleChroma(CameraImage image) {
    if (image.planes.length < 3) return;
    final u = image.planes[1], v = image.planes[2];
    final uvRow = u.bytesPerRow;
    final uvPix = u.bytesPerPixel ?? 1;
    final w = image.width ~/ 2, h = image.height ~/ 2;
    double sum = 0;
    var n = 0;
    const step = 6;
    for (var y = h ~/ 4; y < (3 * h) ~/ 4; y += step) {
      final row = y * uvRow;
      for (var x = w ~/ 4; x < (3 * w) ~/ 4; x += step) {
        final idx = row + x * uvPix;
        if (idx >= u.bytes.length || idx >= v.bytes.length) continue;
        sum += (u.bytes[idx] - 128).abs() + (v.bytes[idx] - 128).abs();
        n++;
      }
    }
    if (n > 0) _lastChromaScore = sum / n;
  }

  Float64List _sampleBlocks(CameraImage image) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final width = image.width;
    final height = image.height;

    final sums = Float64List(_blocksX * _blocksY);
    final counts = List<int>.filled(_blocksX * _blocksY, 0);

    // Ink detection: writing shows up as sharp dark-on-light transitions.
    // A mousepad, floor, or blank desk is uniform and produces almost none.
    var inkEdges = 0;
    var samples = 0;

    const step = 8; // sample every Nth pixel in each direction
    for (int y = 0; y < height; y += step) {
      final by = (y * _blocksY) ~/ height;
      final rowStart = y * rowStride;
      int prev = -1;
      for (int x = 0; x < width; x += step) {
        final idx = rowStart + x;
        if (idx >= bytes.length) continue;
        final v = bytes[idx];
        final b = by * _blocksX + (x * _blocksX) ~/ width;
        sums[b] += v;
        counts[b]++;
        samples++;
        if (prev >= 0) {
          final hi = v > prev ? v : prev;
          if (hi >= 110 && (v - prev).abs() >= 40) inkEdges++;
        }
        prev = v;
      }
    }
    _lastTextScore = samples == 0 ? 0 : inkEdges / samples;
    for (int i = 0; i < sums.length; i++) {
      if (counts[i] > 0) sums[i] /= counts[i];
    }
    return sums;
  }

  /// True when paper appears to run off any edge of the frame — the page
  /// is partly outside the shot and the camera needs to pull back.
  bool _pageCutOff(Float64List blocks) {
    int rowBright(int by) {
      var c = 0;
      for (var bx = 0; bx < _blocksX; bx++) {
        if (blocks[by * _blocksX + bx] >= 140) c++;
      }
      return c;
    }

    int colBright(int bx) {
      var c = 0;
      for (var by = 0; by < _blocksY; by++) {
        if (blocks[by * _blocksX + bx] >= 140) c++;
      }
      return c;
    }

    return rowBright(0) >= 6 ||
        rowBright(_blocksY - 1) >= 6 ||
        colBright(0) >= 5 ||
        colBright(_blocksX - 1) >= 5;
  }

  /// Decodes a captured photo down to a small grayscale thumbnail used for
  /// content comparison between pages.
  Future<_PageThumb?> _thumbOf(Uint8List jpegBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(jpegBytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width, h = image.height;
      image.dispose();
      if (data == null) return null;
      final px = data.buffer.asUint8List();
      final lum = Float64List(w * h);
      for (int i = 0; i < w * h; i++) {
        final o = i * 4;
        lum[i] = 0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2];
      }
      return _PageThumb(lum, w, h);
    } catch (e) {
      debugPrint('Thumb decode failed: $e');
      return null;
    }
  }

  /// Best normalized cross-correlation between two thumbnails over a small
  /// translation search window. ~1.0 means "same content", even if the
  /// paper was nudged a little between shots; brightness/exposure changes
  /// are cancelled by the normalization.
  double _bestCorrelation(_PageThumb a, _PageThumb b) {
    if (a.w != b.w || a.h != b.h) return 0;
    final w = a.w, h = a.h;
    double best = -1;
    const maxShift = 6, step = 2;
    for (int dy = -maxShift; dy <= maxShift; dy += step) {
      for (int dx = -maxShift; dx <= maxShift; dx += step) {
        double sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
        int n = 0;
        for (int y = math.max(0, -dy); y < h && y + dy < h; y++) {
          final rowA = y * w;
          final rowB = (y + dy) * w;
          for (int x = math.max(0, -dx); x < w && x + dx < w; x++) {
            final va = a.lum[rowA + x];
            final vb = b.lum[rowB + x + dx];
            sa += va;
            sb += vb;
            saa += va * va;
            sbb += vb * vb;
            sab += va * vb;
            n++;
          }
        }
        if (n < 100) continue;
        final cov = sab - sa * sb / n;
        final varA = saa - sa * sa / n;
        final varB = sbb - sb * sb / n;
        if (varA <= 0 || varB <= 0) continue;
        final r = cov / math.sqrt(varA * varB);
        if (r > best) best = r;
      }
    }
    return best;
  }

  /// How much of the frame reads as paper — drives too close / too far hints.
  _DistanceHint _distanceHint(Float64List blocks) {
    var bright = 0;
    for (final v in blocks) {
      if (v >= 140) bright++;
    }
    final frac = bright / blocks.length;
    if (frac < 0.25) return _DistanceHint.tooFar;
    if (frac > 0.94) return _DistanceHint.tooClose;
    return _DistanceHint.ok;
  }

  bool _paperLikely(Float64List blocks) {
    // Paper reads as a bright region in the middle of the frame that
    // stands out from what surrounds it (desk, floor). A uniform scene
    // like bare floor has no such center-vs-edge contrast.
    double center = 0, border = 0;
    int nc = 0, nb = 0;
    for (int by = 0; by < _blocksY; by++) {
      for (int bx = 0; bx < _blocksX; bx++) {
        final v = blocks[by * _blocksX + bx];
        if (bx == 0 || by == 0 || bx == _blocksX - 1 || by == _blocksY - 1) {
          border += v;
          nb++;
        } else {
          center += v;
          nc++;
        }
      }
    }
    center /= nc;
    border /= nb;
    // Brightness: very bright center = the page fills most of the frame;
    // otherwise the page must be clearly brighter than its surroundings.
    final brightEnough = center >= 165 || (center >= 120 && center - border >= 12);
    // Ink: a real page has writing on it. Auto-exposure can make a dark
    // mousepad read "bright", but wood grain also fakes some edges — so the
    // bar is higher than pure noise, and paired with the chroma check below.
    final hasInk = _lastTextScore >= 0.012;
    // Color: paper is white/neutral. A bright wooden desk, cardboard, or a
    // lap is warm-toned and fails this even when brightness+edges pass.
    final isNeutral = _lastChromaScore <= 15;
    return brightEnough && hasInk && isNeutral;
  }

  double _motionScore(Float64List cur, Float64List prev) {
    // Cancel uniform brightness shifts so auto-exposure hunting doesn't
    // read as motion and block the capture forever.
    double shift = 0;
    for (int i = 0; i < cur.length; i++) {
      shift += cur[i] - prev[i];
    }
    shift /= cur.length;

    double sum = 0;
    for (int i = 0; i < cur.length; i++) {
      sum += ((cur[i] - prev[i]) - shift).abs();
    }
    return sum / cur.length;
  }

  void _onFrame(CameraImage image) {
    if (_state == _ScanState.capturing) return;

    _sampleChroma(image);
    final blocks = _sampleBlocks(image);
    final last = _lastBlocks;
    _lastBlocks = blocks;
    if (last == null) return;

    final isMoving = _motionScore(blocks, last) > _motionThreshold;
    final now = DateTime.now();

    final hint = _distanceHint(blocks);
    if (hint != _hint) setState(() => _hint = hint);
    final cutOff = hint != _DistanceHint.tooFar && _pageCutOff(blocks);
    if (cutOff != _cutOff) setState(() => _cutOff = cutOff);

    switch (_state) {
      case _ScanState.idle:
        // Waiting for a page to be placed in frame (motion, then settle).
        if (isMoving) {
          setState(() => _state = _ScanState.waitingForStillness);
          _stillSince = null;
        }
        break;

      case _ScanState.waitingForStillness:
        if (isMoving) {
          _stillSince = null; // still moving, reset the still-timer
          if (_noPaper || _samePage) {
            setState(() {
              _noPaper = false;
              _samePage = false;
            });
          }
        } else {
          _stillSince ??= now;
          if (now.difference(_stillSince!) >= _stillDuration) {
            final lastCapture = _lastCaptureBlocks;
            if (hint != _DistanceHint.ok || cutOff) {
              // Wrong distance or the page is cut off — hold and coach.
              _stillSince = now;
            } else if (!_paperLikely(blocks)) {
              // Scene is still but doesn't look like a page — don't snap
              // the floor. Re-check after another still interval.
              _stillSince = now;
              if (!_noPaper) {
                setState(() {
                  _noPaper = true;
                  _samePage = false;
                });
              }
            } else if (lastCapture != null && _motionScore(blocks, lastCapture) <= _duplicateThreshold) {
              // Looks the same as the page just captured — the swap hasn't
              // happened yet, so don't shoot a duplicate.
              _stillSince = now;
              if (!_samePage) {
                setState(() {
                  _samePage = true;
                  _noPaper = false;
                });
              }
            } else {
              _capture();
            }
          }
        }
        break;

      case _ScanState.cooldown:
        // Require motion again (page swapped out) before re-arming.
        if (isMoving) {
          setState(() {
            _state = _ScanState.idle;
            _dupSkipped = false;
            _notAPage = false;
          });
        }
        break;

      case _ScanState.capturing:
        break;
    }
  }

  Future<void> _capture({bool force = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Remember what this page looked like so the next auto-capture only
    // fires once the scene has changed to a genuinely different page.
    final signature = _lastBlocks == null ? null : Float64List.fromList(_lastBlocks!);
    setState(() {
      _state = _ScanState.capturing;
      _noPaper = false;
      _samePage = false;
      _notAPage = false;
    });

    try {
      if (!_webFallback) {
        await controller.stopImageStream();
      }
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();

      // Straighten, boost contrast, sharpen, and verify it's really a page
      // (runs off the UI thread).
      if (mounted) setState(() => _processing = true);
      final detail = await DocumentProcessor.processPageDetailed(bytes);
      if (mounted) setState(() => _processing = false);
      if (!mounted) return;

      // Auto-capture of something that isn't a document (desk, floor, lap):
      // throw it away instead of saving junk. The manual shutter bypasses
      // this so an unusual page can still be forced through.
      if (!force && !detail.isDocument) {
        setState(() {
          _notAPage = true;
          _state = _ScanState.cooldown;
          _stillSince = null;
          _lastBlocks = null;
          if (signature != null) _lastCaptureBlocks = signature;
        });
        if (!_webFallback) {
          await controller.startImageStream(_onFrame);
        }
        return;
      }

      final page = ScannedPage(
        bytes: detail.bytes,
        fileName: 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!mounted) return;
      if (widget.singleShot) {
        Navigator.of(context).pop(<ScannedPage>[page]);
        return;
      }

      // Content-level duplicate check: compare what's actually on this
      // photo against the last saved page. Manual shutter (force) skips it.
      final thumb = await _thumbOf(bytes);
      final prev = _lastAcceptedThumb;
      final isDuplicate = !force &&
          thumb != null &&
          prev != null &&
          _bestCorrelation(thumb, prev) >= _duplicateNcc;
      if (!mounted) return;

      if (isDuplicate) {
        setState(() {
          _dupSkipped = true;
          _state = _ScanState.cooldown;
          _stillSince = null;
          _lastBlocks = null;
          // Also update the cheap pre-capture gate to this (possibly
          // shifted) view of the page so it stops re-firing the shutter.
          if (signature != null) _lastCaptureBlocks = signature;
        });
      } else {
        if (thumb != null) _lastAcceptedThumb = thumb;
        setState(() {
          _pages.add(page);
          _flash = true;
          _dupSkipped = false;
          _state = _ScanState.cooldown;
          _stillSince = null;
          _lastBlocks = null;
          if (signature != null) _lastCaptureBlocks = signature;
        });
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted) setState(() => _flash = false);
        });
      }

      if (!_webFallback) {
        await controller.startImageStream(_onFrame);
      } else {
        setState(() => _state = _ScanState.idle);
      }
    } catch (e) {
      debugPrint('Auto-capture failed: $e');
      if (mounted) setState(() => _state = _ScanState.idle);
      if (!_webFallback) {
        try {
          await controller.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  void _finish() {
    Navigator.of(context).pop(List<ScannedPage>.unmodifiable(_pages));
  }

  void _cancel() {
    Navigator.of(context).pop(const <ScannedPage>[]);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _statusLabel {
    switch (_state) {
      case _ScanState.capturing:
        return _processing ? 'Straightening & sharpening…' : 'Capturing...';
      case _ScanState.cooldown:
        if (_notAPage) return 'That didn\'t look like a page — nothing saved. Use the shutter to force it';
        return _dupSkipped
            ? 'Same page — not saved. Swap to the next page'
            : 'Page ${_pages.length} captured ✓  Slide in the next page';
      case _ScanState.idle:
      case _ScanState.waitingForStillness:
        if (_hint == _DistanceHint.tooFar) return 'Too far — move closer to the page';
        if (_cutOff) return 'Page is cut off — pull back so it all fits';
        if (_hint == _DistanceHint.tooClose) return 'Too close — move back a little';
        if (_state == _ScanState.idle) {
          return _pages.isEmpty ? 'Place a page in frame' : 'Slide in the next page';
        }
        if (_noPaper) return 'No page with writing detected — center the paper';
        if (_samePage) return 'Same page — swap in the next one';
        return 'Hold still...';
    }
  }

  bool get _showWarningIcon => _noPaper || _samePage || _notAPage || _cutOff || _hint != _DistanceHint.ok;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // System back keeps whatever was captured instead of losing it.
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel scan',
          ),
          title: Text(widget.singleShot
              ? 'Retake Page'
              : 'Auto Scan · ${_pages.length} page${_pages.length == 1 ? '' : 's'}'),
        ),
        body: _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
            : !_ready || _controller == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      AnimatedOpacity(
                        opacity: _flash ? 0.7 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: const ColoredBox(color: Colors.white),
                      ),
                      if (_webFallback)
                        Positioned(
                          left: 24,
                          right: 24,
                          top: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Live auto-capture needs the native app — use the shutter button to capture on web.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!widget.singleShot)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 24),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_state == _ScanState.waitingForStillness || (_state == _ScanState.idle && _showWarningIcon))
                                        Padding(
                                          padding: const EdgeInsets.only(right: 10),
                                          child: _hint == _DistanceHint.tooFar
                                              ? const Icon(Icons.zoom_in_rounded, size: 16, color: Colors.amber)
                                              : _cutOff
                                                  ? const Icon(Icons.crop_free_rounded, size: 16, color: Colors.amber)
                                              : _hint == _DistanceHint.tooClose
                                                  ? const Icon(Icons.zoom_out_rounded, size: 16, color: Colors.amber)
                                                  : _noPaper
                                                      ? const Icon(Icons.search_off_rounded, size: 16, color: Colors.amber)
                                                      : _samePage
                                                          ? const Icon(Icons.repeat_rounded, size: 16, color: Colors.amber)
                                                          : const SizedBox(
                                                              width: 14,
                                                              height: 14,
                                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                            ),
                                        ),
                                      Flexible(
                                        child: Text(
                                          _statusLabel,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_pages.isNotEmpty && !widget.singleShot) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 72,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _pages.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                                    itemBuilder: (context, i) => ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Stack(
                                        children: [
                                          Image.memory(
                                            _pages[i].bytes,
                                            width: 54,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                          ),
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              color: Colors.black.withValues(alpha: 0.6),
                                              padding: const EdgeInsets.symmetric(vertical: 1),
                                              child: Text(
                                                'P${i + 1}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Manual shutter — works even if auto-detect is being
                                    // fussy, and bypasses the duplicate-page check.
                                    GestureDetector(
                                      onTap: _state == _ScanState.capturing ? null : () => _capture(force: true),
                                      child: Container(
                                        width: 68,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          border: Border.all(color: Colors.black26, width: 4),
                                        ),
                                        child: _state == _ScanState.capturing
                                            ? const Padding(
                                                padding: EdgeInsets.all(20),
                                                child: CircularProgressIndicator(strokeWidth: 3),
                                              )
                                            : const Icon(Icons.camera_alt_rounded, color: Colors.black87, size: 28),
                                      ),
                                    ),
                                    if (!widget.singleShot)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: _pages.isEmpty ? null : _finish,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: Colors.black,
                                            disabledBackgroundColor: Colors.white24,
                                            disabledForegroundColor: Colors.white54,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          ),
                                          icon: const Icon(Icons.check_rounded),
                                          label: Text(
                                            'Done (${_pages.length})',
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Small grayscale copy of a captured photo, used to compare page content.
class _PageThumb {
  final Float64List lum;
  final int w;
  final int h;
  const _PageThumb(this.lum, this.w, this.h);
}
