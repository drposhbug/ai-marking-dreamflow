// The same conditional-import shape browser_intake_web.dart beside it
// already uses: this file only ever compiles for the browser.
import 'package:web/web.dart' as web;

/// Leaves the app for Stripe's hosted checkout.
///
/// A full same-tab navigation rather than a popup on purpose: the checkout
/// URL only exists after a round trip to our edge function, and by then the
/// browser no longer counts the click as a user gesture, so window.open is
/// exactly the thing a pop-up blocker eats. Stripe brings the teacher back
/// to the return URL the server set.
void redirectTo(String url) => web.window.location.assign(url);

/// The address the app was loaded at — how the Plans screen knows it is
/// looking at a return from Stripe rather than an ordinary visit.
String currentLocation() => web.window.location.href;
