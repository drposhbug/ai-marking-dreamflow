import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A fake edge gateway. Each call is answered by [answer] — the test decides
/// what STRIPE-CHECKOUT and MARKING-PROCESS say — and every request body is
/// kept, because the whole point of the server-side price map is that the
/// client never gets to name a price.
class _FakeEdge {
  final List<({String fn, Map<String, dynamic>? body})> calls = [];
  final Object Function(String fn, Map<String, dynamic>? body) answer;

  _FakeEdge(this.answer);

  Future<FunctionResponse> invoke(String fn, {Map<String, dynamic>? body}) {
    calls.add((fn: fn, body: body));
    final res = answer(fn, body);
    if (res is FunctionResponse) return Future.value(res);
    return Future.error(res);
  }

  Map<String, dynamic>? bodyFor(String action) {
    for (final c in calls) {
      if (c.body?['action'] == action) return c.body;
    }
    return null;
  }

  int countOf(String action) => calls.where((c) => c.body?['action'] == action).length;
}

FunctionResponse _ok(Map<String, dynamic> data) => FunctionResponse(status: 200, data: data);

const _configured = {
  'configured': true,
  'tiers': ['starter', 'pro', 'pro_annual', 'school'],
};

/// A service wired to a fake browser: nothing here touches Supabase,
/// RevenueCat or a real window.
({BillingService billing, _FakeEdge edge, List<String> redirects, List<String?> invalidated}) _web({
  required Object Function(String fn, Map<String, dynamic>? body) answer,
  String location = 'https://app.example/#/plans',
  bool onWeb = true,
}) {
  final edge = _FakeEdge(answer);
  final redirects = <String>[];
  final invalidated = <String?>[];
  final billing = BillingService(
    onWeb: onWeb,
    transport: edge.invoke,
    redirect: redirects.add,
    location: () => location,
    invalidateUsage: invalidated.add,
  );
  return (billing: billing, edge: edge, redirects: redirects, invalidated: invalidated);
}

void main() {
  group('a teacher in a browser can be sold a plan', () {
    test('the server, not the app, decides whether anything is on sale', () async {
      final w = _web(answer: (fn, body) => _ok(_configured));
      await w.billing.loadOfferings();

      expect(w.billing.webCheckoutReady, isTrue);
      expect(w.billing.webCheckoutTiers, containsAll(['starter', 'pro', 'pro_annual', 'school']));
      expect(w.billing.unavailableReason, isEmpty);
      expect(w.edge.calls.single.fn, 'STRIPE-CHECKOUT');
      expect(w.edge.calls.single.body?['action'], 'status');
    });

    test('choosing a tier sends the tier and nothing else, then hands over to Stripe', () async {
      final w = _web(answer: (fn, body) {
        if (body?['action'] == 'status') return _ok(_configured);
        return _ok({'url': 'https://checkout.stripe.com/c/pay/cs_test_123'});
      });
      await w.billing.loadOfferings();

      final outcome = await w.billing.startWebCheckout('pro', teacherId: 'teacher-1');

      expect(outcome, PurchaseOutcome.redirected);
      expect(w.redirects.single, 'https://checkout.stripe.com/c/pay/cs_test_123');
      final sent = w.edge.bodyFor('create')!;
      // The request names a tier. A price, an amount or a plan name in here
      // would be a teacher's chance to pick their own bill.
      expect(sent['tier'], 'pro');
      expect(sent['teacherId'], 'teacher-1');
      expect(sent.keys.toSet(), {'action', 'tier', 'teacherId'});
      // Nothing was granted locally — only the webhook grants.
      expect(w.billing.isPro, isFalse);
    });

    test('a tier the server does not sell never reaches the network', () async {
      final w = _web(answer: (fn, body) => _ok({
            'configured': true,
            'tiers': ['pro'],
          }));
      await w.billing.loadOfferings();

      final outcome = await w.billing.startWebCheckout('school', teacherId: 'teacher-1');

      expect(outcome, PurchaseOutcome.unavailable);
      expect(w.edge.countOf('create'), 0);
      expect(w.redirects, isEmpty);
    });

    test('a signed-out teacher is not sent to a checkout that credits nobody', () async {
      final w = _web(answer: (fn, body) => _ok(_configured));
      await w.billing.loadOfferings();

      final outcome = await w.billing.startWebCheckout('pro', teacherId: '');

      expect(outcome, PurchaseOutcome.unavailable);
      expect(w.edge.countOf('create'), 0);
      expect(w.redirects, isEmpty);
    });

    test('a checkout that cannot be created leaves the teacher where they were', () async {
      final w = _web(answer: (fn, body) {
        if (body?['action'] == 'status') return _ok(_configured);
        return const FunctionException(status: 500, details: {'error': 'stripe unreachable'});
      });
      await w.billing.loadOfferings();

      final outcome = await w.billing.startWebCheckout('pro', teacherId: 'teacher-1');

      expect(outcome, PurchaseOutcome.failed);
      expect(w.redirects, isEmpty);
      expect(w.billing.isPro, isFalse);
    });

    test('a reply with no checkout url is a failure, not a redirect to nowhere', () async {
      final w = _web(answer: (fn, body) {
        if (body?['action'] == 'status') return _ok(_configured);
        return _ok({'ok': true});
      });
      await w.billing.loadOfferings();

      expect(await w.billing.startWebCheckout('pro', teacherId: 'teacher-1'), PurchaseOutcome.failed);
      expect(w.redirects, isEmpty);
    });
  });

  group('managing a web subscription', () {
    test('the portal opens for the signed-in teacher and nobody else', () async {
      final w = _web(answer: (fn, body) {
        if (body?['action'] == 'status') return _ok(_configured);
        return _ok({'url': 'https://billing.stripe.com/p/session_123'});
      });
      await w.billing.loadOfferings();

      expect(await w.billing.openBillingPortal(teacherId: 'teacher-1'), isTrue);
      expect(w.redirects.single, 'https://billing.stripe.com/p/session_123');
      expect(w.edge.bodyFor('portal'), {'action': 'portal', 'teacherId': 'teacher-1'});
    });

    test('a teacher with nothing to manage is not sent anywhere', () async {
      final w = _web(answer: (fn, body) {
        if (body?['action'] == 'status') return _ok(_configured);
        return const FunctionException(status: 404, details: {'error': 'no subscription'});
      });
      await w.billing.loadOfferings();

      expect(await w.billing.openBillingPortal(teacherId: 'teacher-1'), isFalse);
      expect(w.redirects, isEmpty);
    });
  });

  group('a build with no Stripe account behind it', () {
    test('says so honestly and offers no button', () async {
      final w = _web(answer: (fn, body) => _ok({
            'configured': false,
            'message': 'Card payments aren\'t switched on yet.',
          }));
      await w.billing.loadOfferings();

      expect(w.billing.webCheckoutReady, isFalse);
      expect(w.billing.webCheckoutTiers, isEmpty);
      expect(w.billing.unavailableReason, 'Card payments aren\'t switched on yet.');
    });

    test('refuses to start a checkout it knows cannot work', () async {
      final w = _web(answer: (fn, body) => _ok({'configured': false, 'message': 'not set up'}));
      await w.billing.loadOfferings();

      expect(await w.billing.startWebCheckout('pro', teacherId: 'teacher-1'), PurchaseOutcome.unavailable);
      expect(w.edge.countOf('create'), 0);
    });

    test('an unreachable checkout function reads as a connection problem, not a plan', () async {
      final w = _web(answer: (fn, body) => Exception('socket closed'));
      await w.billing.loadOfferings();

      expect(w.billing.webCheckoutReady, isFalse);
      expect(w.billing.unavailableReason, isNotEmpty);
    });

    test('the old dead end is gone — the web no longer says plans are phone-only', () async {
      final w = _web(answer: (fn, body) => _ok(_configured));
      await w.billing.init();

      expect(w.billing.unavailableReason, isNot(contains('phone app')));
    });
  });

  group('coming back from Stripe', () {
    test('landing back on the app grants nothing on its own — the server is asked', () async {
      var plan = 'trial';
      final w = _web(
        location: 'https://app.example/#/plans?checkout=success&session_id=cs_test_1',
        answer: (fn, body) {
          if (fn == 'MARKING-PROCESS') return _ok({'profile': {'plan': plan}});
          return _ok(_configured);
        },
      );

      // The webhook lands between the first ask and the second.
      final result = await w.billing.handleCheckoutReturn(
        teacherId: 'teacher-1',
        attempts: 3,
        gap: Duration.zero,
        onAttempt: (n) {
          if (n == 2) plan = 'pro';
        },
      );

      expect(result, CheckoutReturn.granted);
      expect(w.billing.isPro, isTrue);
      expect(w.edge.countOf('get_profile'), greaterThanOrEqualTo(2));
      // The 45-second usage cache would otherwise show the trial allowance
      // to a teacher who has just paid.
      expect(w.invalidated, ['teacher-1']);
    });

    test('a webhook that has not landed yet is pending, not a grant', () async {
      final w = _web(
        location: 'https://app.example/#/plans?checkout=success',
        answer: (fn, body) {
          if (fn == 'MARKING-PROCESS') return _ok({'profile': {'plan': 'trial'}});
          return _ok(_configured);
        },
      );

      final result = await w.billing.handleCheckoutReturn(teacherId: 'teacher-1', attempts: 2, gap: Duration.zero);

      expect(result, CheckoutReturn.pending);
      expect(w.billing.isPro, isFalse);
      expect(w.invalidated, isEmpty);
    });

    test('a teacher who backed out is told nothing was charged', () async {
      final w = _web(
        location: 'https://app.example/#/plans?checkout=cancelled',
        answer: (fn, body) => _ok(_configured),
      );

      expect(await w.billing.handleCheckoutReturn(teacherId: 'teacher-1'), CheckoutReturn.cancelled);
      expect(w.edge.countOf('get_profile'), 0);
      expect(w.invalidated, isEmpty);
    });

    test('an ordinary visit to the plans screen polls nothing', () async {
      final w = _web(answer: (fn, body) => _ok(_configured));

      expect(await w.billing.handleCheckoutReturn(teacherId: 'teacher-1'), CheckoutReturn.none);
      expect(w.edge.calls, isEmpty);
    });

    test('every paid tier counts as entitled, the trial does not', () {
      expect(BillingService.isPaidPlan('pro'), isTrue);
      expect(BillingService.isPaidPlan('pro_annual'), isTrue);
      expect(BillingService.isPaidPlan('starter'), isTrue);
      expect(BillingService.isPaidPlan('school'), isTrue);
      expect(BillingService.isPaidPlan('trial'), isFalse);
      expect(BillingService.isPaidPlan(''), isFalse);
      expect(BillingService.isPaidPlan('preview'), isFalse);
    });
  });

  group('the phone is untouched', () {
    test('off the web nothing asks Stripe anything', () async {
      final w = _web(onWeb: false, answer: (fn, body) => fail('the phone must not call Stripe'));

      await w.billing.loadOfferings();
      expect(w.edge.calls, isEmpty);
      expect(w.billing.webCheckoutReady, isFalse);
      expect(await w.billing.startWebCheckout('pro', teacherId: 'teacher-1'), PurchaseOutcome.unavailable);
      expect(await w.billing.handleCheckoutReturn(teacherId: 'teacher-1'), CheckoutReturn.none);
      expect(w.redirects, isEmpty);
    });

    test('an unconfigured phone build still says it is on the preview allowance', () async {
      final w = _web(onWeb: false, answer: (fn, body) => fail('the phone must not call Stripe'));
      await w.billing.init();

      expect(w.billing.unavailableReason, contains('preview allowance'));
      expect(w.billing.available, isFalse);
    });
  });
}
