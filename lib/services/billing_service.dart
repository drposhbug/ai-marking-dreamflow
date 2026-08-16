import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// How a purchase attempt ended — the Plans screen reports each differently.
enum PurchaseOutcome { success, cancelled, unavailable, failed }

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

  String? _teacherId;

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
    _teacherId = teacherId;
    try {
      final res = await Purchases.logIn(teacherId);
      _onCustomerInfo(res.customerInfo);
    } catch (e) {
      debugPrint('BillingService.logIn failed: $e');
    }
  }

  Future<void> logOut() async {
    if (!_available) return;
    _teacherId = null;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  void _onCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(entitlementId);
    _managementUrl = info.managementURL;
    if (active != _isPro) {
      _isPro = active;
      notifyListeners();
      _syncPlanToServer();
    }
  }

  /// profiles.plan drives the server-side credit caps — keep it matched to
  /// the entitlement so paying teachers get paid-tier credits immediately.
  Future<void> _syncPlanToServer() async {
    final id = _teacherId;
    if (id == null) return;
    try {
      await AiGradingService().saveProfile(teacherId: id, plan: _isPro ? 'pro' : 'trial');
    } catch (e) {
      debugPrint('BillingService plan sync failed: $e');
    }
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
