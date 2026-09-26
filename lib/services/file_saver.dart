// Hands a finished file to the teacher: a download in the browser, the share
// sheet on a phone. The same conditional-import shape as web_redirect.dart.
//
// Every "export" in the app used to write to getTemporaryDirectory() and
// share from there — which does not exist in a browser, so on the web the
// marks export, the stamped test PDF and the report comments all failed
// silently: the teacher pressed the button and nothing happened.
export 'file_saver_native.dart' if (dart.library.html) 'file_saver_web.dart';
