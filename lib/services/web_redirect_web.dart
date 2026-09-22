// The same conditional-import shape browser_intake_web.dart beside it
// already uses: this file only ever compiles for the browser.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Leaves the app for Stripe's hosted checkout.
///
/// A full same-tab navigation rather than a popup on purpose: the checkout
/// URL only exists after a round trip to our edge function, and by then the
/// browser no longer counts the click as a user gesture, so window.open is
/// exactly the thing a pop-up blocker eats. Stripe brings the teacher back
/// to the return URL the server set.
void redirectTo(String url) => html.window.location.assign(url);

/// The address the app was loaded at — how the Plans screen knows it is
/// looking at a return from Stripe rather than an ordinary visit.
String currentLocation() => html.window.location.href;
