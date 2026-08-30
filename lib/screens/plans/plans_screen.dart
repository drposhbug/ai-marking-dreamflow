import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/auth_service.dart';
import 'package:marking_prokect_v2/services/billing_service.dart';
import 'package:marking_prokect_v2/theme.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// A tier as the app describes it. Prices here are the fallback copy — when
/// the store has the product, its own localized price wins, so a teacher in
/// Canada sees CAD without an app update.
class _Tier {
  final String id;
  final String name;
  final String fallbackPrice;
  final String period;
  final String credits;
  final List<String> perks;
  final bool highlight;

  /// Substrings to look for in the store product id, and the RevenueCat
  /// package type that would also identify this tier.
  final List<String> productHints;
  final PackageType? packageType;

  const _Tier({
    required this.id,
    required this.name,
    required this.fallbackPrice,
    required this.period,
    required this.credits,
    required this.perks,
    required this.productHints,
    this.packageType,
    this.highlight = false,
  });
}

const _tiers = <_Tier>[
  _Tier(
    id: 'starter',
    name: 'Starter',
    fallbackPrice: '\$6.99',
    period: '/month',
    credits: 'About 200 papers a month, marked overnight',
    perks: ['Marking on every subject', 'Answer keys and learned keys', 'Google Drive export'],
    productHints: ['starter'],
  ),
  _Tier(
    id: 'pro',
    name: 'Pro',
    fallbackPrice: '\$14.99',
    period: '/month',
    credits: 'About 450 papers a month marked overnight, or 90 on the spot',
    perks: ['Everything in Starter', 'Mark a whole class set on the spot', 'Lesson planning assistant', 'Priority marking queue'],
    productHints: ['pro_month', 'pro.month', 'monthly'],
    packageType: PackageType.monthly,
    highlight: true,
  ),
  _Tier(
    id: 'pro_annual',
    name: 'Pro Annual',
    fallbackPrice: '\$119.99',
    period: '/year',
    credits: 'About 300 papers a month overnight — two months free vs monthly',
    perks: ['Everything in Pro', 'Two months free vs monthly'],
    productHints: ['annual', 'year'],
    packageType: PackageType.annual,
  ),
  _Tier(
    id: 'school',
    name: 'School',
    fallbackPrice: '\$24.99',
    period: '/month',
    credits: 'About 760 papers a month marked overnight, or 150 on the spot',
    perks: ['Everything in Pro', 'Built for a full teaching load', 'Department invoicing on request'],
    productHints: ['school'],
  ),
];

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  UsageSummary? _usage;
  String? _busyTierId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      // Offerings can arrive after startup (or not at all before sign-in) —
      // ask again so prices are live by the time the cards paint.
      await context.read<BillingService>().loadOfferings();
      if (!mounted) return;
      final auth = context.read<AuthService>().currentUser;
      if (auth == null) return;
      try {
        final u = await AiGradingService().getUsage(teacherId: auth.id);
        if (mounted) setState(() => _usage = u);
      } catch (e) {
        debugPrint('PlansScreen usage load failed: $e');
      }
    });
  }

  /// The store package that matches a tier, or null when that product isn't
  /// published yet.
  Package? _packageFor(_Tier tier, List<Package> packages) {
    for (final p in packages) {
      final id = p.storeProduct.identifier.toLowerCase();
      if (tier.productHints.any(id.contains)) return p;
    }
    if (tier.packageType != null) {
      for (final p in packages) {
        if (p.packageType == tier.packageType) return p;
      }
    }
    return null;
  }

  Future<void> _buy(_Tier tier, Package? package) async {
    final billing = context.read<BillingService>();
    if (package == null) {
      _snack('${tier.name} isn\'t available in the store yet.');
      return;
    }
    setState(() => _busyTierId = tier.id);
    final outcome = await billing.buy(package);
    if (!mounted) return;
    setState(() => _busyTierId = null);
    switch (outcome) {
      case PurchaseOutcome.success:
        _snack('${tier.name} is active — welcome aboard! Your credits have been upgraded.');
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.unavailable:
        _snack('Purchases aren\'t switched on in this build yet.');
      case PurchaseOutcome.failed:
        _snack('That purchase didn\'t go through. Nothing was charged.');
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final billing = context.watch<BillingService>();
    final packages = billing.packages;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
        title: const Text('Plans'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _CurrentPlanCard(usage: _usage, isPro: billing.isPro),
          const SizedBox(height: 18),
          Text(
            'Every paid plan gives 10% to charities that help kids learn.',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          for (final tier in _tiers) ...[
            _TierCard(
              tier: tier,
              package: _packageFor(tier, packages),
              busy: _busyTierId == tier.id,
              purchasable: billing.available,
              onBuy: () => _buy(tier, _packageFor(tier, packages)),
            ),
            const SizedBox(height: 12),
          ],
          if (billing.unavailableReason.isNotEmpty)
            Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AiMarkerColors.neutral),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        billing.unavailableReason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (billing.available)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () async {
                    final ok = await billing.restorePurchases();
                    if (!mounted) return;
                    _snack(ok ? 'Purchases restored — Pro is active.' : 'No previous purchases found for this account.');
                  },
                  child: const Text('Restore purchases'),
                ),
                if (billing.isPro)
                  TextButton(
                    onPressed: billing.presentCustomerCenter,
                    child: const Text('Manage subscription'),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Marking overnight costs about a fifth of marking on the spot, which is why every plan goes so much further that way. Credits are cost-weighted, not a flat test count: a short multiple-choice quiz uses far less than a six-page problem set, and re-marking the same paper is free. Subscriptions renew until cancelled and can be cancelled any time in the store.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final UsageSummary? usage;
  final bool isPro;
  const _CurrentPlanCard({required this.usage, required this.isPro});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    usage == null ? 'Your plan' : 'Your plan · ${usage!.planLabel}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  usage == null ? '—' : '${usage!.monthPct}% used',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: (usage?.monthPct ?? 0) / 100, minHeight: 8),
            ),
            const SizedBox(height: 8),
            Text(
              usage == null
                  ? 'Marking credits for this month.'
                  : 'This month: ${usage!.monthPct}% · this week: ${usage!.weekPct}% · today: ${usage!.dayPct}%.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final _Tier tier;
  final Package? package;
  final bool busy;
  final bool purchasable;
  final VoidCallback onBuy;

  const _TierCard({required this.tier, required this.package, required this.busy, required this.purchasable, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = package?.storeProduct.priceString ?? tier.fallbackPrice;
    final canBuy = purchasable && package != null && !busy;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: tier.highlight ? BorderSide(color: cs.primary, width: 2) : BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tier.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (tier.highlight) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                    child: Text('BEST VALUE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                  ),
                ],
                const Spacer(),
                Text(price, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(tier.period, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral)),
              ],
            ),
            const SizedBox(height: 6),
            Text(tier.credits, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AiMarkerColors.neutral, height: 1.4)),
            const SizedBox(height: 10),
            for (final perk in tier.perks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(perk, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: tier.highlight
                  ? FilledButton(
                      onPressed: canBuy ? onBuy : null,
                      child: busy ? const _ButtonSpinner() : Text('Choose ${tier.name}'),
                    )
                  : OutlinedButton(
                      onPressed: canBuy ? onBuy : null,
                      child: busy ? const _ButtonSpinner() : Text('Choose ${tier.name}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
