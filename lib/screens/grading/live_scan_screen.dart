import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// A live "CamScanner-style" auto-capture screen.
///
/// Holds the camera preview open continuously. When the frame goes
/// still (teacher has placed/held a page steady) for [stillDuration],
/// it auto-captures, hands the bytes to [onCapture], shows a brief
/// flash/confirmation, then re-arms itself — waiting for motion
/// (the page being swapped) before it will fire again. This lets a
/// teacher keep sliding pages under the camera without tapping
/// anything.
class LiveScanScreen extends StatefulWidget {
  /// Called every time a page is auto-captured. Return true to keep
  /// scanning (multi-page mode), or false to close the scanner after
  /// this capture.
  final Future<bool> Function(Uint8List bytes, String fileName) onCapture;

  const LiveScanScreen({super.key, required this.onCapture});

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

enum _ScanState { idle, waitingForStillness, capturing, cooldown }

class _LiveScanScreenState extends State<LiveScanScreen> {
  CameraController? _controller;
  bool _ready = false;
  String? _error;

  _ScanState _state = _ScanState.idle;
  DateTime? _stillSince;
  double? _lastSampleLuma;
  int _captureCount = 0;

  // Tune these to taste.
  static const double _motionThreshold = 6.0; // luma delta to count as "moving"
  static const Duration _stillDuration = Duration(milliseconds: 700);
  static const Duration _cooldownDuration = Duration(milliseconds: 1200);

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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _ready = true;
      });
      await controller.startImageStream(_onFrame);
    } catch (e) {
      setState(() => _error = 'Could not start camera: $e');
    }
  }

  // Cheap "how much did this frame change vs the last one" estimate.
  // Samples a sparse grid of Y-plane pixels instead of the whole frame.
  double _sampleLuma(CameraImage image) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final width = image.width;
    final height = image.height;

    const gridStep = 16; // sample every Nth pixel in each direction
    double sum = 0;
    int count = 0;
    for (int y = 0; y < height; y += gridStep) {
      final rowStart = y * rowStride;
      for (int x = 0; x < width; x += gridStep) {
        final idx = rowStart + x;
        if (idx < bytes.length) {
          sum += bytes[idx];
          count++;
        }
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  void _onFrame(CameraImage image) {
    if (_state == _ScanState.capturing) return;

    final luma = _sampleLuma(image);
    final last = _lastSampleLuma;
    _lastSampleLuma = luma;
    if (last == null) return;

    final delta = (luma - last).abs();
    final isMoving = delta > _motionThreshold;
    final now = DateTime.now();

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
        } else {
          _stillSince ??= now;
          if (now.difference(_stillSince!) >= _stillDuration) {
            _capture();
          }
        }
        break;

      case _ScanState.cooldown:
        // Require motion again (page swapped out) before re-arming.
        if (isMoving) {
          setState(() => _state = _ScanState.idle);
        }
        break;

      case _ScanState.capturing:
        break;
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() => _state = _ScanState.capturing);

    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      _captureCount++;
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final keepScanning = await widget.onCapture(bytes, fileName);

      if (!mounted) return;
      if (!keepScanning) {
        Navigator.of(context).pop();
        return;
      }

      await controller.startImageStream(_onFrame);
      setState(() {
        _state = _ScanState.cooldown;
        _stillSince = null;
      });
      await Future<void>.delayed(_cooldownDuration);
    } catch (e) {
      debugPrint('Auto-capture failed: $e');
      if (mounted) setState(() => _state = _ScanState.idle);
      try {
        await controller.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String get _statusLabel => switch (_state) {
        _ScanState.idle => 'Place a page in frame',
        _ScanState.waitingForStillness => 'Hold still...',
        _ScanState.capturing => 'Capturing...',
        _ScanState.cooldown => 'Captured ✓  Slide in the next page',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Auto Scan  ($_captureCount captured)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : !_ready || _controller == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 40,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_state == _ScanState.waitingForStillness)
                              const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                              ),
                            Text(_statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}