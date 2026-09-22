// Reads the text off a page, using whatever this platform has.
//
// Same shape as `browser_intake.dart` and `web_image_picker.dart` beside
// it: one conditional export, two implementations, and nothing above this
// line that knows which one it got. What differs between them is not only
// speed — it is how much of the page they can read at all, which is why
// every reading carries an [OcrTrust] with it.
export 'page_text_reader_native.dart' if (dart.library.html) 'page_text_reader_web.dart';
