import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// A small AdMob banner for free-trial teachers on a phone. Paying teachers
/// never see it; the caller decides who qualifies.
///
/// What the ad network gets, and what it does not:
///   * Ads are requested NON-PERSONALISED (`nonPersonalizedAds: true`), so
///     Google serves them on context, not on a profile of the teacher. No
///     tracking permission is asked for on iOS, so no advertising id either.
///   * Content is capped at a G rating: it sits beside students' work.
///   * The request carries no keywords, no content URL and nothing from the
///     app. Student names, pages and marks never reach the ad SDK; the banner
///     is a separate native view that cannot read the rest of the screen.
///
/// Every impression and its revenue is also reported to RevenueCat's ad
/// tracker, so ad income sits beside subscription income in one dashboard.
class FreeTierBannerAd extends StatefulWidget {
  const FreeTierBannerAd({super.key});

  // Real ad unit ids arrive at build time. In a debug build with none set,
  // Google's public test units are used so the slot can be seen working;
  // a release build with none set shows nothing at all.
  static const _envAndroid = String.fromEnvironment('ADMOB_BANNER_ANDROID');
  static const _envIos = String.fromEnvironment('ADMOB_BANNER_IOS');
  static const _testAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testIos = 'ca-app-pub-3940256099942544/2934735716';

  static String get adUnitId {
    if (kIsWeb) return '';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _envAndroid.isNotEmpty ? _envAndroid : (kDebugMode ? _testAndroid : '');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _envIos.isNotEmpty ? _envIos : (kDebugMode ? _testIos : '');
    }
    return '';
  }

  @override
  State<FreeTierBannerAd> createState() => _FreeTierBannerAdState();
}

class _FreeTierBannerAdState extends State<FreeTierBannerAd> {
  static Future<void>? _started;
  BannerAd? _ad;
  bool _loaded = false;

  static Future<void> _startOnce() => _started ??= () async {
        await MobileAds.instance.initialize();
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(maxAdContentRating: MaxAdContentRating.g),
        );
      }();

  @override
  void initState() {
    super.initState();
    final unit = FreeTierBannerAd.adUnitId;
    if (unit.isEmpty) return;
    _startOnce().then((_) {
      if (!mounted) return;
      final ad = BannerAd(
        adUnitId: unit,
        size: AdSize.banner,
        request: const AdRequest(nonPersonalizedAds: true),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _loaded = true);
            _track(() => Purchases.adTracker.trackAdLoaded(AdLoadedData(
                  mediatorName: AdMediatorName.adMob,
                  adFormat: AdFormat.banner,
                  adUnitId: unit,
                  impressionId: _impressionId(ad),
                )));
          },
          onAdImpression: (ad) => _track(() => Purchases.adTracker.trackAdDisplayed(AdDisplayedData(
                mediatorName: AdMediatorName.adMob,
                adFormat: AdFormat.banner,
                adUnitId: unit,
                impressionId: _impressionId(ad),
              ))),
          onPaidEvent: (ad, valueMicros, precision, currency) =>
              _track(() => Purchases.adTracker.trackAdRevenue(AdRevenueData(
                    mediatorName: AdMediatorName.adMob,
                    adFormat: AdFormat.banner,
                    adUnitId: unit,
                    impressionId: _impressionId(ad),
                    revenueMicros: valueMicros.round(),
                    currency: currency,
                    precision: _precision(precision),
                  ))),
          onAdFailedToLoad: (ad, error) {
            debugPrint('FreeTierBannerAd failed to load: ${error.message}');
            ad.dispose();
          },
        ),
      );
      _ad = ad;
      ad.load();
    }).catchError((Object e) {
      debugPrint('FreeTierBannerAd could not start: $e');
    });
  }

  static String _impressionId(Ad ad) => ad.responseInfo?.responseId ?? '';

  static AdRevenuePrecision _precision(PrecisionType p) => switch (p) {
        PrecisionType.precise => AdRevenuePrecision.exact,
        PrecisionType.estimated => AdRevenuePrecision.estimated,
        PrecisionType.publisherProvided => AdRevenuePrecision.publisherDefined,
        PrecisionType.unknown => AdRevenuePrecision.unknown,
      };

  /// RevenueCat is only configured when billing is on in this build, and
  /// its ad tracker is experimental. Reporting must never break the ad.
  static void _track(Future<void> Function() call) {
    call().catchError((Object e) => debugPrint('RevenueCat ad tracking skipped: $e'));
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).cardColor,
      alignment: Alignment.center,
      width: double.infinity,
      height: ad.size.height.toDouble(),
      child: SizedBox(width: ad.size.width.toDouble(), child: AdWidget(ad: ad)),
    );
  }
}
