import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/web_redirect.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How a purchase attempt ended — the Plans screen reports each differently.
///
/// [redirected] is web-only: the teacher has been handed to Stripe's hosted
/// checkout and this tab is on its way out. Nothing has been bought yet.
///
/// [alreadySubscribedElsewhere] is the server refusing to charge twice: this
/// account is already paying through the other shop. Nothing was charged and
/// nothing is wrong — the teacher has the plan, just not from here.
enum PurchaseOutcome { success, cancelled, unavailable, failed, redirected, alreadySubscribedElsewhere }

/// Which shop a teacher's plan was actually bought in.
///
/// Markless takes money through two rails that cannot see each other: the app
/// stores (RevenueCat validates the receipt) and Stripe on the web. Only the
/// shop that took the money can change or cancel the subscription, so the app
/// has to know which one that was before it offers to do either — and before
/// it offers to sell the same plan again.
enum PlanSource {
  /// Google Play or the App Store, through the phone app.
  appStore,

  /// Stripe, in a browser.
  web,

  /// Nobody is charging this account, or the server could not say. The app
  /// treats these the same way on purpose: it stays quiet about where the
  /// plan lives rather than naming the wrong shop.
  unknown,
}

extension PlanSourceWords on PlanSource {
  /// Where the money goes, in the words a teacher would use.
  String get shopName => switch (this) {
        PlanSource.appStore => 'the app store',
        PlanSource.web => 'the web',
        PlanSource.unknown => 'somewhere else',
      };

  /// What to tell a teacher who is looking at a plan they cannot buy here
  /// because they already have it, bought somewhere else.
  String get manageItThere => switch (this) {
        PlanSource.appStore =>
          'Your plan was bought in the phone app, so Google Play or the App Store handles the billing. Change or cancel it there — buying again here would charge you twice.',
        PlanSource.web =>
          'Your plan was bought on the web, so it is billed by card rather than through the store. Open the billing page on the Markless website to change or cancel it — buying again here would charge you twice.',
        PlanSource.unknown => '',
      };

  static PlanSource parse(Object? raw) => switch (raw?.toString().trim().toLowerCase()) {
        'revenuecat' => PlanSource.appStore,
        'stripe' => PlanSource.web,
        _ => PlanSource.unknown,
      };
}

/// What a return from Stripe's checkout turned out to be.
///
/// [granted] is the ONLY one that means a plan — and even then the app
/// learned it by asking the server what the webhook wrote, never by reading
/// the URL it was sent back to.
enum CheckoutReturn {
  /// An ordinary visit to the Plans screen.
  none,

  /// The teacher backed out of Stripe. Nothing was charged.
  cancelled,

  /// The webhook has landed and the account is on a paid plan.
  granted,

  /// They paid, but the webhook hasn't been written yet (or the payment is
  /// still processing). Nothing is granted here — the next refresh will see it.
  pending,
}

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
///
/// In a browser there are no stores and no RevenueCat SDK, so the web takes
/// an entirely separate road: STRIPE-CHECKOUT hands back a hosted checkout
/// URL, the teacher pays on Stripe's own page, and STRIPE-WEBHOOK — not this
/// class, not the redirect back — writes profiles.plan. Everything below the
/// "web checkout" heading is web-only and none of it runs on a phone.
class BillingService extends ChangeNotifier {
  /// [onWeb], [transport], [redirect], [location] and [invalidateUsage] all
  /// exist so a test can hold the browser, the network and the clock in its
  /// hand. The defaults are exactly what the shipped app does.
  BillingService({
    bool? onWeb,
    EdgeTransport? transport,
    void Function(String url)? redirect,
    String Function()? location,
    void Function(String? teacherId)? invalidateUsage,
  })  : _onWeb = onWeb ?? kIsWeb,
        _transport = transport ?? _liveTransport,
        _redirect = redirect ?? redirectTo,
        _location = location ?? currentLocation,
        _invalidateUsage = invalidateUsage ?? AiGradingService.invalidateUsageCache;

  final bool _onWeb;
  final EdgeTransport _transport;
  final void Function(String url) _redirect;
  final String Function() _location;
  final void Function(String? teacherId) _invalidateUsage;

  static Future<FunctionResponse> _liveTransport(String function, {Map<String, dynamic>? body}) =>
      Supabase.instance.client.functions.invoke(function, body: body);

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
  /// (missing store, no key) — the service just stays unavailable.
  ///
  /// On the web there is no store SDK to configure, so this asks the server
  /// whether card checkout is switched on instead. It never leaves the
  /// RevenueCat side [available]: restore, the paywall and the customer
  /// centre are store features that do not exist in a browser.
  Future<void> init() async {
    if (_onWeb) {
      await loadWebCheckout();
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
    // The Plans screen calls this on open. In a browser the equivalent
    // question is "does the server have Stripe prices for these tiers", so
    // one call from the screen serves both roads.
    if (_onWeb) return loadWebCheckout();
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
    // Already paying by card on the web? The store cannot see that
    // subscription and would happily start a second one beside it, on its
    // own renewal date, which the teacher would then have to cancel in two
    // different places. STRIPE-CHECKOUT refuses the mirror image of this.
    if (subscribedInTheOtherShop) return PurchaseOutcome.alreadySubscribedElsewhere;
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
    if (_onWeb) {
      // A signed-out browser is not on anyone's plan.
      _isPro = false;
      _webPlan = '';
      notifyListeners();
      return;
    }
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

  // ───────────────────────── Web checkout (Stripe) ─────────────────────────
  //
  // None of this runs on a phone. The phone keeps RevenueCat exactly as it
  // was; a browser gets Stripe Checkout, because a browser has no store.

  /// True when this build is running in a browser at all.
  bool get onWeb => _onWeb;

  /// Whether the server has a Stripe key and at least one price configured.
  /// False until [loadWebCheckout] has asked, so an unconfigured build shows
  /// [unavailableReason] rather than a button that cannot work.
  bool _webCheckoutReady = false;
  bool get webCheckoutReady => _webCheckoutReady;

  /// The tier ids the server actually holds a Stripe price for. A tier not
  /// in here is not offered — the price map lives on the server, and the app
  /// asks what is in it rather than assuming.
  Set<String> _webTiers = const {};
  Set<String> get webCheckoutTiers => _webTiers;

  /// The plan the server last reported for this account in a browser. Only
  /// ever written from a server answer.
  String _webPlan = '';
  String get webPlan => _webPlan;

  /// Plans that mean "this teacher is paying". `preview` is a founder
  /// account and `trial` is the free allowance, so neither counts — matching
  /// PLAN_CAPS in MARKING-PROCESS, where only these four have a price.
  static const paidPlans = {'starter', 'pro', 'pro_annual', 'school'};

  static bool isPaidPlan(String? plan) => paidPlans.contains((plan ?? '').trim().toLowerCase());

  /// The plan the server last reported, and which shop it came from. Both are
  /// only ever written from a server answer — the client cannot decide it is
  /// entitled, and cannot decide who charged it.
  String _serverPlan = '';
  PlanSource _planSource = PlanSource.unknown;

  /// Which shop is charging for this account's plan. [PlanSource.unknown]
  /// while nobody is, or while the server hasn't been asked yet.
  PlanSource get planSource => _planSource;

  /// True when this account is on a paid plan that was bought in the OTHER
  /// shop — a store subscription seen from a browser, or a web subscription
  /// seen from the phone app.
  ///
  /// This is the whole point of knowing the source. A teacher in this state
  /// already has what the Plans screen is selling, and buying again would
  /// start a second subscription on a second rail with a second renewal date,
  /// only one of which they can cancel from where they are standing.
  bool get subscribedInTheOtherShop {
    if (!isPaidPlan(_serverPlan)) return false;
    return _onWeb ? _planSource == PlanSource.appStore : _planSource == PlanSource.web;
  }

  /// What to tell that teacher. Empty when there is nothing to say.
  String get otherShopNote => subscribedInTheOtherShop ? _planSource.manageItThere : '';

  /// Asks the server what this account is entitled to and who is charging
  /// for it. Cheap, and safe to call whenever the Plans screen opens.
  ///
  /// Never throws and never clears what it already knew on a failure: a
  /// flaky network must not turn "you already subscribed on your phone" into
  /// an invitation to subscribe again.
  Future<void> refreshEntitlement(String teacherId) async {
    if (teacherId.trim().isEmpty) return;
    try {
      final res = await _transport('MARKING-PROCESS', body: {
        'action': 'get_profile',
        'teacherId': teacherId,
      });
      final data = res.data;
      if (data is! Map || data['profile'] is! Map) return;
      final profile = data['profile'] as Map;
      _serverPlan = (profile['plan'] ?? '').toString();
      _planSource = PlanSourceWords.parse(profile['plan_source']);
      if (_onWeb) _webPlan = _serverPlan;
      notifyListeners();
    } catch (e) {
      debugPrint('BillingService.refreshEntitlement failed: $e');
    }
  }

  /// Asks STRIPE-CHECKOUT what it can sell. No identity needed and nothing
  /// is charged — it is the honest-message call, so that a build with no
  /// Stripe account behind it says so instead of offering a dead button.
  Future<void> loadWebCheckout() async {
    if (!_onWeb) return;
    try {
      final res = await _transport('STRIPE-CHECKOUT', body: {'action': 'status'});
      final data = res.data;
      if (data is Map && data['configured'] == true) {
        _webTiers = {
          for (final t in (data['tiers'] as List? ?? const [])) t.toString(),
        };
        _webCheckoutReady = _webTiers.isNotEmpty;
        _unavailableReason = _webCheckoutReady
            ? ''
            : 'No plans are on sale on the web yet — you\'re on the preview allowance.';
      } else {
        _webCheckoutReady = false;
        _webTiers = const {};
        // The server writes this message, so a half-configured deployment
        // can say which half. Falling back rather than inventing one.
        final message = data is Map ? (data['message'] ?? '').toString() : '';
        _unavailableReason = message.isNotEmpty
            ? message
            : 'Card payments aren\'t switched on in this build yet — you\'re on the preview allowance.';
      }
    } catch (e) {
      debugPrint('BillingService.loadWebCheckout failed: $e');
      _webCheckoutReady = false;
      _webTiers = const {};
      _unavailableReason = 'Couldn\'t reach the checkout — check your connection and try again.';
    }
    notifyListeners();
  }

  /// Starts a Stripe Checkout Session for [tier] and hands the teacher over.
  ///
  /// The request carries a tier name and the teacher's own id and NOTHING
  /// else: no price, no amount, no plan. The server looks the price up in
  /// its own map and refuses a tier that isn't in it, so a teacher editing
  /// this request can only ever change which of four published prices they
  /// are asked to pay — and the edge function checks their JWT, so they
  /// cannot even buy for somebody else's account.
  ///
  /// Returns [PurchaseOutcome.redirected] once the browser is on its way to
  /// Stripe. Nothing is granted here; see [handleCheckoutReturn].
  Future<PurchaseOutcome> startWebCheckout(String tier, {required String teacherId}) async {
    if (!_onWeb) return PurchaseOutcome.unavailable;
    if (teacherId.trim().isEmpty) {
      _unavailableReason = 'Sign in first so the plan lands on your account.';
      notifyListeners();
      return PurchaseOutcome.unavailable;
    }
    // Don't send a teacher to a checkout the server has already said it
    // can't build.
    if (!_webCheckoutReady || !_webTiers.contains(tier)) return PurchaseOutcome.unavailable;
    try {
      final res = await _transport('STRIPE-CHECKOUT', body: {
        'action': 'create',
        'teacherId': teacherId,
        'tier': tier,
      });
      final data = res.data;
      // The server refuses to charge an account that is already paying
      // through the store. That is a correct answer, not a failure — say so,
      // and record where the plan actually lives so the screen can point
      // there instead of showing a buy button that will be refused again.
      if (data is Map && data['error'] == 'already_subscribed') {
        _planSource = PlanSourceWords.parse(data['rail']);
        _serverPlan = (data['plan'] ?? '').toString();
        notifyListeners();
        return PurchaseOutcome.alreadySubscribedElsewhere;
      }
      final url = data is Map ? (data['url'] ?? '').toString() : '';
      if (url.isEmpty) {
        debugPrint('BillingService.startWebCheckout got no url: $data');
        return PurchaseOutcome.failed;
      }
      _redirect(url);
      return PurchaseOutcome.redirected;
    } catch (e) {
      // A 409 may surface as a thrown FunctionException depending on the
      // transport, so the same answer is recognised here too. Missing it
      // would tell a teacher the checkout broke when in fact they are
      // already subscribed.
      if (e.toString().contains('already_subscribed')) {
        return PurchaseOutcome.alreadySubscribedElsewhere;
      }
      debugPrint('BillingService.startWebCheckout failed: $e');
      return PurchaseOutcome.failed;
    }
  }

  /// Sends the teacher to Stripe's billing portal to change their card or
  /// cancel. Same guard as everything else: the server builds the portal
  /// session from the Stripe customer it recorded against THIS teacher id,
  /// so a teacher cannot open someone else's billing page.
  ///
  /// Returns false (and changes nothing) when there is no subscription to
  /// manage — a teacher who bought in the phone app manages it in the store.
  Future<bool> openBillingPortal({required String teacherId}) async {
    if (!_onWeb || !_webCheckoutReady || teacherId.trim().isEmpty) return false;
    try {
      final res = await _transport('STRIPE-CHECKOUT', body: {
        'action': 'portal',
        'teacherId': teacherId,
      });
      final data = res.data;
      final url = data is Map ? (data['url'] ?? '').toString() : '';
      if (url.isEmpty) return false;
      _redirect(url);
      return true;
    } catch (e) {
      debugPrint('BillingService.openBillingPortal failed: $e');
      return false;
    }
  }

  /// Works out whether this page load is a return from Stripe, and if it is,
  /// asks the server what the webhook wrote.
  ///
  /// Landing on `?checkout=success` proves nothing — a teacher can type that
  /// URL. So the success path here does exactly one thing the URL cannot do:
  /// it reads profiles.plan back off the server, which only STRIPE-WEBHOOK
  /// (signature-verified, service role) can have written. Until that says a
  /// paid plan, the answer is [CheckoutReturn.pending] and nothing changes.
  Future<CheckoutReturn> handleCheckoutReturn({
    required String teacherId,
    int attempts = 6,
    Duration gap = const Duration(seconds: 2),
    void Function(int attempt)? onAttempt,
  }) async {
    if (!_onWeb) return CheckoutReturn.none;
    final where = _location();
    if (where.contains('checkout=cancelled')) return CheckoutReturn.cancelled;
    if (!where.contains('checkout=success')) return CheckoutReturn.none;
    if (teacherId.trim().isEmpty) return CheckoutReturn.pending;

    // Stripe redirects the moment the payment is taken; the webhook is a
    // separate call that usually lands within a second or two. Polling a
    // handful of times is the difference between "Pro is active" and a
    // teacher staring at the trial allowance they just paid to leave.
    for (var attempt = 1; attempt <= attempts; attempt++) {
      onAttempt?.call(attempt);
      final plan = await _fetchServerPlan(teacherId);
      if (isPaidPlan(plan)) {
        _webPlan = plan!;
        _isPro = true;
        // The usage meter caches for 45 seconds. Without this the teacher's
        // brand-new allowance would show as the old one for most of a minute.
        _invalidateUsage(teacherId);
        notifyListeners();
        return CheckoutReturn.granted;
      }
      if (attempt < attempts && gap > Duration.zero) await Future<void>.delayed(gap);
    }
    return CheckoutReturn.pending;
  }

  /// profiles.plan as the server reports it, or null when it can't be read.
  Future<String?> _fetchServerPlan(String teacherId) async {
    try {
      final res = await _transport('MARKING-PROCESS', body: {
        'action': 'get_profile',
        'teacherId': teacherId,
      });
      final data = res.data;
      if (data is Map && data['profile'] is Map) {
        return ((data['profile'] as Map)['plan'] ?? '').toString();
      }
    } catch (e) {
      debugPrint('BillingService._fetchServerPlan failed: $e');
    }
    return null;
  }
}
