// supabase/functions/_shared/entitlement.ts
//
// One subscription, two shops.
//
// A teacher can pay for Markless through the stores (RevenueCat validates the
// receipt) or through Stripe on the web. Those are two independent billing
// rails that have never known about each other, and before this file existed
// both wrote `profiles.plan` directly. That is a fight with two losers:
//
//   Monday   teacher subscribes on the phone  -> plan = pro   (RevenueCat)
//   Tuesday  teacher subscribes on the web    -> plan = pro   (Stripe)
//   March    the phone subscription lapses    -> plan = trial (RevenueCat)
//
// On that last line the teacher loses a plan they are still paying Stripe for,
// because an EXPIRATION from one rail overwrote a live subscription on the
// other. Whoever wrote last won, and last had nothing to do with who was
// actually entitled.
//
// ── THE MODEL ────────────────────────────────────────────────────────────
// Each rail owns one column and writes only that column:
//
//   profiles.plan_revenuecat   what the stores say, and nothing else
//   profiles.plan_stripe       what Stripe says, and nothing else
//   profiles.plan              DERIVED: the better of the two
//   profiles.plan_source       DERIVED: which rail the derived plan came from
//
// So the webhooks cannot clobber each other — there is no shared cell to
// clobber. A revoke from one rail drops that rail to `trial` and the other
// rail's live subscription simply keeps winning. `plan` is still the single
// column MARKING-PROCESS meters against, so nothing downstream changes.
//
// The derivation runs in SQL (`public.apply_entitlement`, defined in
// SETUP-DB) inside one UPDATE, so two webhooks landing in the same
// millisecond cannot interleave a read with a write. The ranking lives there
// and ONLY there — see `plan_rank`. This file deliberately does not reimplement
// it, because two rankings that disagree is the bug this whole file exists to
// prevent.
//
// What is left here is the small amount both webhooks and STRIPE-CHECKOUT
// need in TypeScript: the names of the rails, and whether a given plan string
// means the teacher is paying someone.

/// A billing rail: somewhere a teacher's money actually comes from.
export type Rail = "revenuecat" | "stripe";

/// What `public.apply_entitlement` hands back: both rails as they now stand,
/// plus the two derived columns. `plan` is what the teacher actually gets and
/// what MARKING-PROCESS meters against; `plan_source` is the rail it came
/// from, so a teacher can be sent to the right shop to cancel.
///
/// Declared here rather than inferred, because supabase-js types an RPC
/// result as `{}` and every field read off it would otherwise be a silent
/// `undefined` — on the one code path where being wrong means a teacher
/// keeps or loses a plan they paid for.
export interface EntitlementRow {
  plan: string | null;
  plan_source: Rail | null;
  plan_revenuecat: string | null;
  plan_stripe: string | null;
}

/// Where a rail's money goes, in words a teacher recognises. Used in the
/// message that stops them buying the same thing twice.
export const RAIL_LABEL: Record<Rail, string> = {
  revenuecat: "the app store",
  stripe: "the web",
};

/// The tiers that mean somebody is being charged. `trial` and `preview` are
/// not here: nobody pays for those, so nothing has to be protected from a
/// second purchase.
///
/// Kept in step with PLAN_CAPS in MARKING-PROCESS and with `plan_rank` in
/// SETUP-DB. A tier added to one and not the others is a teacher who either
/// cannot be metered or cannot be protected.
export const PAID_PLANS = ["starter", "pro", "pro_annual", "school"];

/// The plan a rail reports, in the one spelling the rest of the system uses.
/// Anything unrecognised becomes `trial`, which grants nothing — a typo in a
/// product id must not hand out an allowance.
export function normalisePlan(plan: unknown): string {
  const p = String(plan ?? "").trim().toLowerCase();
  return PAID_PLANS.includes(p) ? p : "trial";
}

/// Whether this plan string means the teacher is currently being charged.
export function isPaidPlan(plan: unknown): boolean {
  return PAID_PLANS.includes(String(plan ?? "").trim().toLowerCase());
}

/// The rail that is NOT this one. There are two, and the code that asks
/// "is the teacher already paying somewhere else?" should not have to
/// hard-code which somewhere else that is.
export function otherRail(rail: Rail): Rail {
  return rail === "revenuecat" ? "stripe" : "revenuecat";
}

/// The `profiles` column a rail writes. A rail writes this column and no
/// other — that is the whole point of the model.
export function railColumn(rail: Rail): string {
  return rail === "revenuecat" ? "plan_revenuecat" : "plan_stripe";
}
