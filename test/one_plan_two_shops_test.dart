import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Markless takes money through two shops that cannot see each other: the app
/// stores, and Stripe on the web. These are the app's half of keeping that
/// one subscription — the server's half is proved against real Postgres in
/// tool/sql/entitlement.test.mjs.
///
/// What has to be true: a teacher already paying in one shop is never sold
/// the same thing again in the other, is told where the plan actually lives,
/// and is never told they are unsubscribed because one shop said so.

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
}

FunctionResponse _ok(Map<String, dynamic> data) => FunctionResponse(status: 200, data: data);

/// A profile as MARKING-PROCESS' get_profile returns it.
FunctionResponse _profile({String? plan, String? source}) => _ok({
      'profile': {'teacher_id': 't1', 'plan': plan, 'plan_source': source},
    });

({BillingService billing, _FakeEdge edge}) _service({
  required Object Function(String fn, Map<String, dynamic>? body) answer,
  required bool onWeb,
}) {
  final edge = _FakeEdge(answer);
  return (
    billing: BillingService(
      onWeb: onWeb,
      transport: edge.invoke,
      redirect: (_) {},
      location: () => 'https://app.example/#/plans',
      invalidateUsage: (_) {},
    ),
    edge: edge,
  );
}

void main() {
  group('reading which shop a plan was bought in', () {
    test('the two rails the server names are understood, and nothing else is', () {
      expect(PlanSourceWords.parse('revenuecat'), PlanSource.appStore);
      expect(PlanSourceWords.parse('stripe'), PlanSource.web);
      // A rail the server does not know about must not become a shop the app
      // then names to a teacher.
      expect(PlanSourceWords.parse('paypal'), PlanSource.unknown);
      expect(PlanSourceWords.parse(null), PlanSource.unknown);
      expect(PlanSourceWords.parse(''), PlanSource.unknown);
    });
  });

  group('a teacher who already pays in the other shop', () {
    test('in a browser, a store subscription stops the web selling it again', () async {
      final s = _service(onWeb: true, answer: (fn, body) => _profile(plan: 'pro', source: 'revenuecat'));
      await s.billing.refreshEntitlement('t1');

      expect(s.billing.planSource, PlanSource.appStore);
      expect(s.billing.subscribedInTheOtherShop, isTrue);
      // The teacher is told where it lives, and warned what a second purchase
      // would actually do.
      expect(s.billing.otherShopNote, contains('phone app'));
      expect(s.billing.otherShopNote, contains('twice'));
    });

    test('on a phone, a web subscription stops the store selling it again', () async {
      final s = _service(onWeb: false, answer: (fn, body) => _profile(plan: 'school', source: 'stripe'));
      await s.billing.refreshEntitlement('t1');

      expect(s.billing.planSource, PlanSource.web);
      expect(s.billing.subscribedInTheOtherShop, isTrue);
      expect(s.billing.otherShopNote, contains('web'));
    });

    test('the shop they are standing in is not "the other shop"', () async {
      // Bought on the web, looking at the web: this is where they manage it,
      // so the ordinary Manage subscription route applies and nothing is
      // blocked.
      final s = _service(onWeb: true, answer: (fn, body) => _profile(plan: 'pro', source: 'stripe'));
      await s.billing.refreshEntitlement('t1');
      expect(s.billing.subscribedInTheOtherShop, isFalse);
      expect(s.billing.otherShopNote, isEmpty);
    });

    test('nobody on a free plan is told they already subscribed', () async {
      for (final plan in ['trial', 'preview', '', null]) {
        final s = _service(onWeb: true, answer: (fn, body) => _profile(plan: plan, source: 'revenuecat'));
        await s.billing.refreshEntitlement('t1');
        expect(s.billing.subscribedInTheOtherShop, isFalse, reason: 'plan was "$plan"');
      }
    });

    test('an unnamed shop blocks nothing, because it would name the wrong one', () async {
      // The server could not say where the plan came from. Refusing a sale
      // here would strand a teacher who genuinely wants to buy, and naming a
      // shop would be a guess about their money.
      final s = _service(onWeb: true, answer: (fn, body) => _profile(plan: 'pro', source: null));
      await s.billing.refreshEntitlement('t1');
      expect(s.billing.planSource, PlanSource.unknown);
      expect(s.billing.subscribedInTheOtherShop, isFalse);
    });
  });

  group('the server refusing a second subscription', () {
    test('a refusal reads as "you already have it", not as a broken checkout', () async {
      final s = _service(onWeb: true, answer: (fn, body) {
        if (body?['action'] == 'status') {
          return _ok({'configured': true, 'tiers': ['pro']});
        }
        // What STRIPE-CHECKOUT answers for an account already paying the
        // store: 409, nothing charged, nothing created.
        return _ok({
          'error': 'already_subscribed',
          'rail': 'revenuecat',
          'plan': 'pro',
          'message': 'This account already has a plan through the app store.',
        });
      });
      await s.billing.loadOfferings();

      final outcome = await s.billing.startWebCheckout('pro', teacherId: 't1');
      expect(outcome, PurchaseOutcome.alreadySubscribedElsewhere);
      // And the app now knows where the plan lives, so the screen can stop
      // offering a button the server will refuse again.
      expect(s.billing.planSource, PlanSource.appStore);
      expect(s.billing.subscribedInTheOtherShop, isTrue);
    });

    test('a refusal thrown by the transport is still not reported as a failure', () async {
      final s = _service(onWeb: true, answer: (fn, body) {
        if (body?['action'] == 'status') {
          return _ok({'configured': true, 'tiers': ['pro']});
        }
        return FunctionException(status: 409, details: {'error': 'already_subscribed'});
      });
      await s.billing.loadOfferings();

      expect(await s.billing.startWebCheckout('pro', teacherId: 't1'),
          PurchaseOutcome.alreadySubscribedElsewhere);
    });
  });

  group('not losing a plan to a flaky network', () {
    test('a failed refresh leaves what was already known alone', () async {
      var fail = false;
      final s = _service(onWeb: true, answer: (fn, body) {
        if (fail) return StateError('network down');
        return _profile(plan: 'pro', source: 'revenuecat');
      });
      await s.billing.refreshEntitlement('t1');
      expect(s.billing.subscribedInTheOtherShop, isTrue);

      // The refresh that fails must not turn "you already subscribed on your
      // phone" back into an invitation to subscribe again.
      fail = true;
      await s.billing.refreshEntitlement('t1');
      expect(s.billing.subscribedInTheOtherShop, isTrue);
      expect(s.billing.planSource, PlanSource.appStore);
    });

    test('a signed-out session asks the server nothing', () async {
      final s = _service(onWeb: true, answer: (fn, body) => _profile(plan: 'pro', source: 'stripe'));
      await s.billing.refreshEntitlement('   ');
      expect(s.edge.calls, isEmpty);
    });
  });
}
