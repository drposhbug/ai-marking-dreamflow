/// Sending the whole window somewhere else is a browser gesture. On a phone
/// there is no window to send, so these do nothing and the checkout path
/// that needs them is never taken (BillingService only calls them on web).
void redirectTo(String url) {}

/// The address bar, or empty off the web.
String currentLocation() => '';
