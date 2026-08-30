import 'package:marking_prokect_v2/services/dropped_intake.dart';

/// Dragging a folder onto the window and pasting a screenshot are browser
/// gestures. There is no such thing on a phone, so off the web this hands
/// back nothing and the screen simply never shows a drop target.
class BrowserIntake {
  void dispose() {}
}

BrowserIntake? startBrowserIntake({
  required void Function(bool hovering) onHover,
  required void Function(List<DroppedFile> files) onDropped,
  required void Function(List<DroppedFile> files) onPasted,
}) =>
    null;
