import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

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
  // RevenueCat public SDK key. EMPTY disables billing entirely (no
  // configure call, no store contact) — the test_ key crashed the app on
  // device, so billing stays off until the real goog_ key is set here.
  // Public by design once set — safe to ship in the APK.
  static const _apiKey = '';
  static const entitlementId = 'markless Pro';

  bool _available = false;
  bool get available => _available;

  bool _isPro = false;
  bool get isPro => _isPro;

  String? _managementUrl;
  String? get managementUrl => _managementUrl;

  String? _teacherId;

  /// Configure once at app start. Safe to call when billing isn't possible
  /// (web, missing store, no key) — the service just stays unavailable.
  Future<void> init() async {
    if (kIsWeb || _apiKey.isEmpty) return;
    try {
      await Purchases.setLogLevel(kReleaseMode ? LogLevel.warn : LogLevel.debug);
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _available = true;
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } catch (e) {
      debugPrint('BillingService.init failed: $e');
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
