import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

/// How a teacher wants to be told a page has been captured.
enum CaptureAlert {
  /// A short tone. For a phone propped on a stand, where the teacher is
  /// looking at the paper rather than the screen and needs to know when to
  /// slide the next page in.
  sound,

  /// A brief vibration. For a teacher holding the phone in one hand and
  /// flipping pages with the other — they can feel it without a noise going
  /// off in a quiet staffroom.
  buzz,

  /// Neither. The screen still flashes.
  silent,
}

/// Tells the teacher a page is in, without them having to watch the screen.
///
/// Uses the platform's own click/alert sound and haptics rather than a
/// bundled audio file: nothing to download, nothing to keep in sync with
/// the system volume, and it respects the phone's silent switch the way a
/// teacher would expect in a staffroom.
class CaptureFeedback {
  static const _kKey = 'ai_marker.capture_alert.v1';
  final LocalStore _store;

  CaptureFeedback({LocalStore? store}) : _store = store ?? const LocalStore();

  CaptureAlert _mode = CaptureAlert.sound;
  CaptureAlert get mode => _mode;

  /// Loads the teacher's choice. Defaults to sound: a propped phone is the
  /// setup this exists for, and it is the mode a teacher who hasn't chosen
  /// yet is most likely to want.
  Future<CaptureAlert> load(String teacherId) async {
    try {
      final raw = await _store.getString('$_kKey.$teacherId');
      _mode = CaptureAlert.values.cast<CaptureAlert?>().firstWhere(
                (m) => m?.name == raw,
                orElse: () => null,
              ) ??
          CaptureAlert.sound;
    } catch (e) {
      debugPrint('CaptureFeedback.load failed: $e');
      _mode = CaptureAlert.sound;
    }
    return _mode;
  }

  Future<void> setMode(String teacherId, CaptureAlert mode) async {
    _mode = mode;
    await _store.setString('$_kKey.$teacherId', mode.name);
  }

  /// Fired the moment a page is captured. Deliberately short: this happens
  /// once per page through a stack of thirty, so anything longer than a
  /// blip becomes something a teacher turns off.
  Future<void> pageCaptured() async {
    try {
      switch (_mode) {
        case CaptureAlert.sound:
          await SystemSound.play(SystemSoundType.click);
        case CaptureAlert.buzz:
          // Light, not the long buzz of a notification — the teacher is
          // holding the phone, so a nudge is enough.
          await HapticFeedback.lightImpact();
        case CaptureAlert.silent:
          break;
      }
    } catch (e) {
      // Never let feedback break a scan.
      debugPrint('CaptureFeedback.pageCaptured failed: $e');
    }
  }

  /// A different, heavier signal for "that one didn't count" — a duplicate
  /// page, or a shot that wasn't a document. A teacher watching the paper
  /// rather than the screen needs to know the difference between a page
  /// going in and a page being rejected.
  Future<void> pageRejected() async {
    try {
      switch (_mode) {
        case CaptureAlert.sound:
          await SystemSound.play(SystemSoundType.alert);
        case CaptureAlert.buzz:
          await HapticFeedback.heavyImpact();
        case CaptureAlert.silent:
          break;
      }
    } catch (e) {
      debugPrint('CaptureFeedback.pageRejected failed: $e');
    }
  }

  /// Cycles sound → buzz → silent, for the toggle on the scan screen.
  CaptureAlert next() => switch (_mode) {
        CaptureAlert.sound => CaptureAlert.buzz,
        CaptureAlert.buzz => CaptureAlert.silent,
        CaptureAlert.silent => CaptureAlert.sound,
      };

  static String labelFor(CaptureAlert m) => switch (m) {
        CaptureAlert.sound => 'Sound',
        CaptureAlert.buzz => 'Buzz',
        CaptureAlert.silent => 'Silent',
      };

  static IconData iconFor(CaptureAlert m) => switch (m) {
        CaptureAlert.sound => Icons.volume_up_rounded,
        CaptureAlert.buzz => Icons.vibration_rounded,
        CaptureAlert.silent => Icons.volume_off_rounded,
      };
}
