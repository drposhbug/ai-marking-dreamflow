import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';

/// Where an OAuth provider sends a teacher back to.
///
/// This shipped wrong: the web build sent Google the phone app's deep link,
/// `com.markless.app://login-callback`. A browser cannot open a custom
/// scheme, so the session never came back and sign-in sat on a spinner until
/// a three-minute timeout. Nothing failed loudly, because nothing failed —
/// the app was waiting for a callback that could not physically arrive.
void main() {
  group('the address a browser is sent back to', () {
    test('is the page the teacher started from', () {
      expect(
        webOAuthRedirectFrom(Uri.parse('https://markless.app/app/#/login')),
        'https://markless.app/app/',
      );
    });

    test('never a custom scheme, which is what broke web sign-in', () {
      final url = webOAuthRedirectFrom(Uri.parse('https://markless.app/app/#/login'));
      expect(url.startsWith('https://'), isTrue);
      expect(url, isNot(contains('com.markless.app')));
    });

    test('the router\'s fragment is dropped, being ours and not the provider\'s', () {
      expect(
        webOAuthRedirectFrom(Uri.parse('https://x.vercel.app/app/#/plans?checkout=success')),
        'https://x.vercel.app/app/',
      );
    });

    test('a query on the page is dropped too — Supabase appends its own', () {
      // The marketing site hands the address across as ?email=..., and that
      // must not be carried into the provider round trip.
      expect(
        webOAuthRedirectFrom(Uri.parse('https://x.vercel.app/app/?email=a%40b.com#/login')),
        'https://x.vercel.app/app/',
      );
    });

    test('it survives being hosted under a path, which is how Pages serves it', () {
      expect(
        webOAuthRedirectFrom(Uri.parse('https://drposhbug.github.io/ai-marking-dreamflow/app/#/login')),
        'https://drposhbug.github.io/ai-marking-dreamflow/app/',
      );
    });

    test('a port is kept, so a local build comes back to itself', () {
      expect(
        webOAuthRedirectFrom(Uri.parse('http://localhost:8080/#/login')),
        'http://localhost:8080/',
      );
    });

    test('off the web it is still the deep link the phone app registers', () {
      // These tests do not run in a browser, so this is the native branch.
      expect(oauthRedirectUrl(), 'com.markless.app://login-callback');
    });
  });
}
