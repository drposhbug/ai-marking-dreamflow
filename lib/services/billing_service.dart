import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// How a purchase attempt ended — the Plans screen reports each differently.
enum PurchaseOutcome { success, cancelled, unavailable, failed }

/// What this teacher's subscription has put towards the give-back the Plans
/// screen promises.
///
/// Every figure here comes off their own RevenueCat entitlement and the
/// store's price for the product behind it. When either is missing the
/// amounts stay null and Settings says so, because a made-up total is worse
/// than no total on a claim about giving money away.
class GivingSummary {
  /// The share of every payment that goes to the give-back. Must match the
  /// promise on the Plans screen.
  static const share = 0.10;

  /// PLACEHOLDER — no charity partner has been chosen yet. Nothing in the
  /// app may name one until it has been.
  static const charityPlaceholder = 'a children\'s education charity';

  /// Payments the teacher has actually been charged for.
  final int paymentsMade;

  /// About what those payments have generated, in [currencyCode]. Null when
  /// the store hasn't told us the price of their plan.
  final double? generatedToDate;

  /// What one payment on their current plan generates.
  final double? perPayment;
  final String currencyCode;

  /// 'month' or 'year' — how often [perPayment] recurs.
  final String period;

  /// On a free trial: entitled, but not charged yet.
  final bool inTrial;

  const GivingSummary({
    this.paymentsMade = 0,
    this.generatedToDate,
    this.perPayment,
    this.currencyCode = '',
    this.period = 'month',
    this.inTrial = false,
  });
}

/// RevenueCat subscriptions for Markless.
///
/// One entitlement gates the paid experience: "markless Pro". The products
/// behind it (monthly / yearly / lifetime) live in the RevenueCat dashboard
/// and arrive through Offerings — the app never hard-codes prices, so
/// price changes and experiments need no app update.
///
/// The server meters marking credits off profiles.plan, so whenever the
/// entitlement flips this service syncs the plan to the backend.
class BillingService extends ChangeNotifier {
  // RevenueCat public SDK key. Ships empty: pass the real one at build time
  // with --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx (or paste it into
  // _bakedKey). EMPTY disables billing entirely — no configure call, no
  // store contact — because the test_ key crashed the app on device.
  // Public by design once set — safe to ship in the APK.
  // Each store has its own public key: goog_ for Play, appl_ for App Store.
  static const _bakedAndroidKey = '';
  static const _bakedIosKey = '';
  static const _envAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _envIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static String get _apiKey {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    if (isIos) return _envIosKey.isNotEmpty ? _envIosKey : _bakedIosKey;
    return _envAndroidKey.isNotEmpty ? _envAndroidKey : _bakedAndroidKey;
  }
  static const entitlementId = 'markless Pro';

  bool _available = false;
  bool get available => _available;

  bool _isPro = false;
  bool get isPro => _isPro;

  String? _managementUrl;
  String? get managementUrl => _managementUrl;

  /// Plain-English reason the Plans screen can't sell anything, so teachers
  /// see why instead of a dead button.
  String _unavailableReason = '';
  String get unavailableReason => _unavailableReason;

  /// Packages from the current RevenueCat Offering — empty until the store
  /// products are published and attached to an Offering.
  List<Package> _packages = const [];
  List<Package> get packages => _packages;

  /// The teacher's own entitlement record — start date, period type and the
  /// product behind it. Everything the give-back total is derived from.
  EntitlementInfo? _entitlement;

  GivingSummary _giving = const GivingSummary();
  GivingSummary get giving => _giving;

  /// Days left on a free trial, or null when they aren't in one. Drives the
  /// trial-ending notification, so it has to be the store's own date rather
  /// than a guess from when the account was made.
  int? get trialDaysLeft {
    final ent = _entitlement;
    if (ent == null || !ent.isActive || ent.periodType != PeriodType.trial) return null;
    final ends = DateTime.tryParse(ent.expirationDate ?? '');
    if (ends == null) return null;
    final days = ends.difference(DateTime.now()).inHours / 24;
    return days <= 0 ? 0 : days.ceil();
  }

  /// Configure once at app start. Safe to call when billing isn't possible
  /// (web, missing store, no key) — the service just stays unavailable.
  Future<void> init() async {
    if (kIsWeb) {
      _unavailableReason = 'Plans are bought in the phone app.';
      return;
    }
    if (_apiKey.isEmpty) {
      _unavailableReason = 'In-app purchases aren\'t switched on in this build yet — you\'re on the preview allowance.';
      return;
    }
    try {
      await Purchases.setLogLevel(kReleaseMode ? LogLevel.warn : LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _available = true;
      _onCustomerInfo(await Purchases.getCustomerInfo());
      await loadOfferings();
    } catch (e) {
      debugPrint('BillingService.init failed: $e');
      _unavailableReason = 'Couldn\'t reach the store — check your connection and try again.';
    }
    notifyListeners();
  }

  /// Pulls the current Offering. Prices shown in the app come from the store
  /// itself, so they're always right for the teacher's country.
  Future<void> loadOfferings() async {
    if (!_available) return;
    try {
      final offerings = await Purchases.getOfferings();
      _packages = offerings.current?.availablePackages ?? const [];
      if (_packages.isEmpty) {
        _unavailableReason = 'No plans are published in the store yet.';
      } else {
        _unavailableReason = '';
      }
      // The give-back total needs a price, and the price only exists once
      // the Offering has landed.
      _recomputeGiving();
      notifyListeners();
    } catch (e) {
      debugPrint('BillingService.loadOfferings failed: $e');
      _unavailableReason = 'Couldn\'t load plans from the store.';
      notifyListeners();
    }
  }

  /// Buys a package straight from the app's own plans screen — no
  /// RevenueCat-hosted paywall needed.
  Future<PurchaseOutcome> buy(Package package) async {
    if (!_available) return PurchaseOutcome.unavailable;
    try {
      final res = await Purchases.purchase(PurchaseParams.package(package));
      _onCustomerInfo(res.customerInfo);
      return _isPro ? PurchaseOutcome.success : PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return PurchaseOutcome.cancelled;
      debugPrint('BillingService.buy failed (${code.name}): $e');
      return PurchaseOutcome.failed;
    } catch (e) {
      debugPrint('BillingService.buy failed: $e');
      return PurchaseOutcome.failed;
    }
  }

  /// Ties purchases to the teacher's account id so Pro follows them across
  /// devices and reinstalls (RevenueCat aliases the anonymous id).
  Future<void> logIn(String teacherId) async {
    if (!_available) return;
    try {
      final res = await Purchases.logIn(teacherId);
      _onCustomerInfo(res.customerInfo);
    } catch (e) {
      debugPrint('BillingService.logIn failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_available) return;
    _entitlement = null;
    _giving = const GivingSummary();
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(entitlementId);
    _managementUrl = info.managementURL;
    _entitlement = info.entitlements.all[entitlementId];
    _recomputeGiving();
    if (active != _isPro) {
      _isPro = active;
      // profiles.plan is written by the REVENUECAT-WEBHOOK function and by
      // nothing else, deliberately: a teacher must not be able to grant
      // themselves a paid tier by asking the app to save one.
      notifyListeners();
    }
  }

  /// Works out the give-back from the teacher's own subscription.
  ///
  /// RevenueCat gives the app an entitlement, not a receipt book, so the
  /// total is built from the two facts it does hand over: the date the
  /// subscription first started, and the store's current price for the
  /// product behind it. That makes it a count of payments taken, priced at
  /// today's price — honest to within a price change, which is why Settings
  /// says "about". With no price (offerings not loaded, product unpublished)
  /// the total stays null rather than being guessed at.
  void _recomputeGiving() {
    final ent = _entitlement;
    if (ent == null || !ent.isActive) {
      _giving = const GivingSummary();
      return;
    }

    final product = _productFor(ent.productIdentifier);
    final annual = _isAnnual(ent.productIdentifier, product);
    final perPayment = product == null ? null : product.price * GivingSummary.share;

    // A trial is entitled but not charged — it has generated nothing yet,
    // and saying otherwise would be the exact fabrication to avoid.
    if (ent.periodType == PeriodType.trial) {
      _giving = GivingSummary(
        perPayment: perPayment,
        currencyCode: product?.currencyCode ?? '',
        period: annual ? 'year' : 'month',
        inTrial: true,
      );
      return;
    }

    final started = DateTime.tryParse(ent.originalPurchaseDate);
    final payments = started == null ? 0 : paymentsSince(started, DateTime.now(), annual: annual);
    _giving = GivingSummary(
      paymentsMade: payments,
      generatedToDate: perPayment == null ? null : perPayment * payments,
      perPayment: perPayment,
      currencyCode: product?.currencyCode ?? '',
      period: annual ? 'year' : 'month',
    );
  }

  /// Payments taken between [start] and [now], counting the one at signup.
  static int paymentsSince(DateTime start, DateTime now, {required bool annual}) {
    if (!now.isAfter(start)) return 0;
    var months = (now.year - start.year) * 12 + (now.month - start.month);
    if (now.day < start.day) months--;
    if (months < 0) months = 0;
    return annual ? (months ~/ 12) + 1 : months + 1;
  }

  /// The store product behind an entitlement. Play appends the base plan to
  /// the id ("markless_pro:monthly"), so the match is on the leading part.
  StoreProduct? _productFor(String productIdentifier) {
    final wanted = productIdentifier.split(':').first.toLowerCase();
    if (wanted.isEmpty) return null;
    for (final p in _packages) {
      if (p.storeProduct.identifier.split(':').first.toLowerCase() == wanted) return p.storeProduct;
    }
    return null;
  }

  bool _isAnnual(String productIdentifier, StoreProduct? product) {
    final id = (product?.identifier ?? productIdentifier).toLowerCase();
    if (id.contains('annual') || id.contains('year')) return true;
    for (final p in _packages) {
      if (p.storeProduct.identifier == product?.identifier) return p.packageType == PackageType.annual;
    }
    return false;
  }

  /// Shows the remotely-configured RevenueCat paywall unless the teacher
  /// already has Pro. Returns true when they end up entitled.
  Future<bool> presentPaywall() async {
    if (!_available) return false;
    try {
      await RevenueCatUI.presentPaywallIfNeeded(entitlementId);
      _onCustomerInfo(await Purchases.getCustomerInfo());
      return _isPro;
    } catch (e) {
      debugPrint('BillingService.presentPaywall failed: $e');
      return false;
    }
  }

  /// RevenueCat's Customer Center: manage/cancel subscription, restore,
  /// refund requests — all remotely configured.
  Future<void> presentCustomerCenter() async {
    if (!_available) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } catch (e) {
      debugPrint('BillingService.presentCustomerCenter failed: $e');
    }
  }

  /// Replays store purchases onto this account (new phone, reinstall).
  Future<bool> restorePurchases() async {
    if (!_available) return false;
    try {
      _onCustomerInfo(await Purchases.restorePurchases());
      return _isPro;
    } catch (e) {
      debugPrint('BillingService.restorePurchases failed: $e');
      return false;
    }
  }
}
