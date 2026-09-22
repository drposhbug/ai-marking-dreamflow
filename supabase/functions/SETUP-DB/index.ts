// One-time database setup for AI Marker. Safe to run repeatedly.
import postgres from "npm:postgres";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  try {
    const url = Deno.env.get("SUPABASE_DB_URL");
    if (!url) return Response.json({ error: "SUPABASE_DB_URL not available" }, { status: 500 });
    const sql = postgres(url, { prepare: false });
    await sql`
      create table if not exists public.answer_keys (
        id uuid primary key default gen_random_uuid(),
        teacher_id text not null,
        name text not null,
        subject text,
        total_marks numeric,
        key_json jsonb not null,
        created_at timestamptz not null default now()
      )`;
    await sql`alter table public.answer_keys enable row level security`;
    await sql`create index if not exists answer_keys_teacher_idx on public.answer_keys (teacher_id, created_at desc)`;
    await sql`
      create table if not exists public.grade_cache (
        content_hash text primary key,
        provider text not null,
        raw jsonb not null,
        image_hashes jsonb,
        created_at timestamptz not null default now()
      )`;
    await sql`alter table public.grade_cache add column if not exists image_hashes jsonb`;
    await sql`alter table public.grade_cache enable row level security`;
    await sql`create index if not exists grade_cache_created_idx on public.grade_cache (created_at)`;
    await sql`
      create table if not exists public.feedback_code_usage (
        id bigint generated always as identity primary key,
        bank text not null,
        code text not null,
        kind text not null,
        created_at timestamptz not null default now()
      )`;
    await sql`alter table public.feedback_code_usage enable row level security`;
    await sql`create index if not exists feedback_code_usage_bank_code_idx on public.feedback_code_usage (bank, code)`;
    await sql`
      create table if not exists public.profiles (
        teacher_id text primary key,
        email text,
        name text,
        school text,
        region text,
        marking_feedback jsonb,
        updated_at timestamptz not null default now()
      )`;
    await sql`alter table public.profiles enable row level security`;
    await sql`create index if not exists profiles_email_idx on public.profiles (email)`;
    await sql`
      create table if not exists public.schools (
        name text primary key,
        region text,
        created_at timestamptz not null default now()
      )`;
    await sql`alter table public.schools enable row level security`;
    await sql`create index if not exists schools_name_lower_idx on public.schools (lower(name) text_pattern_ops)`;
    await sql`
      create table if not exists public.usage_log (
        id bigint generated always as identity primary key,
        teacher_id text not null,
        action text not null,
        input_tokens int not null default 0,
        output_tokens int not null default 0,
        cost_usd numeric not null default 0,
        created_at timestamptz not null default now()
      )`;
    await sql`alter table public.usage_log enable row level security`;
    await sql`create index if not exists usage_log_teacher_time_idx on public.usage_log (teacher_id, created_at desc)`;
    // Named submissions_cloud because the original template left behind a
    // legacy public.submissions table with an incompatible schema.
    await sql`
      create table if not exists public.submissions_cloud (
        id text primary key,
        teacher_id text not null,
        payload jsonb not null,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )`;
    await sql`alter table public.submissions_cloud enable row level security`;
    await sql`create index if not exists submissions_cloud_teacher_time_idx on public.submissions_cloud (teacher_id, created_at desc)`;
    // Classes, students and student↔class links: one JSON array per teacher
    // and kind, so a teacher's setup survives a wiped app or a new phone.
    await sql`
      create table if not exists public.collections_cloud (
        teacher_id text not null,
        kind text not null,
        payload jsonb not null,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        primary key (teacher_id, kind)
      )`;
    await sql`alter table public.collections_cloud enable row level security`;
    // Marking schemes: the legacy table predates per-class schemes.
    await sql`
      create table if not exists public.presets (
        id text primary key,
        teacher_id text not null,
        class_id text,
        name text,
        grading_mode text,
        criteria jsonb,
        harshness int,
        notes text,
        is_default boolean not null default false,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )`;
    await sql`alter table public.presets add column if not exists class_id text`;
    await sql`alter table public.presets add column if not exists grading_mode text`;
    await sql`alter table public.presets add column if not exists criteria jsonb`;
    await sql`alter table public.presets add column if not exists harshness int`;
    await sql`alter table public.presets add column if not exists notes text`;
    await sql`alter table public.presets add column if not exists is_default boolean not null default false`;
    await sql`create index if not exists presets_teacher_idx on public.presets (teacher_id)`;
    // Overnight (Batch API) marking runs in flight. `meta` holds what
    // normalize() needs per paper when the results land hours later.
    await sql`
      create table if not exists public.marking_batches (
        batch_id text primary key,
        teacher_id text not null,
        status text not null default 'in_progress',
        meta jsonb,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )`;
    await sql`alter table public.marking_batches enable row level security`;
    await sql`create index if not exists marking_batches_teacher_idx on public.marking_batches (teacher_id, created_at desc)`;
    await sql`alter table public.profiles add column if not exists plan text`;
    // ── One subscription, two shops ──────────────────────────────────────
    // A teacher can pay through the stores (RevenueCat) or on the web
    // (Stripe). Each rail owns one column and writes only that column;
    // `plan` is derived from both. Before this, both webhooks wrote `plan`
    // directly, so a cancellation on one rail wiped out a live subscription
    // on the other. See supabase/functions/_shared/entitlement.ts.
    await sql`alter table public.profiles add column if not exists plan_revenuecat text`;
    await sql`alter table public.profiles add column if not exists plan_stripe text`;
    await sql`alter table public.profiles add column if not exists plan_source text`;
    // Every profile that has a plan today got it from the stores: Stripe has
    // never been switched on. Backfilling anything else would invent a
    // subscription nobody has.
    await sql`update public.profiles set plan_revenuecat = plan
               where plan_revenuecat is null and plan is not null and plan <> 'trial'`;

    // How generous a tier is. THE one place this order is written down: the
    // webhooks and the app read the result, never re-rank it themselves.
    // pro_annual sits BELOW pro on purpose — it bills $10.00/mo against
    // Pro's $14.99, so it cannot carry Pro's allowance.
    await sql`
      create or replace function public.plan_rank(p text)
      returns int language sql immutable as $fn$
        select case lower(coalesce(p, ''))
          when 'school' then 4
          when 'pro' then 3
          when 'pro_annual' then 2
          when 'starter' then 1
          else 0
        end
      $fn$`;

    // The plan a teacher actually gets. `a` is always what the stores say,
    // `b` always what Stripe says. A teacher paying on both rails keeps the
    // better of the two rather than whichever webhook landed last; a tie
    // goes to the stores, which came first and whose refunds are slower.
    await sql`
      create or replace function public.best_plan(a text, b text)
      returns text language sql immutable as $fn$
        select case
          when greatest(public.plan_rank(a), public.plan_rank(b)) = 0 then 'trial'
          when public.plan_rank(a) >= public.plan_rank(b) then lower(a)
          else lower(b)
        end
      $fn$`;

    // Which rail the winning plan came from, so the app can send a teacher
    // to the right place to cancel — and can refuse to sell them a second
    // subscription in the other shop.
    await sql`
      create or replace function public.best_plan_rail(a text, b text)
      returns text language sql immutable as $fn$
        select case
          when greatest(public.plan_rank(a), public.plan_rank(b)) = 0 then null
          when public.plan_rank(a) >= public.plan_rank(b) then 'revenuecat'
          else 'stripe'
        end
      $fn$`;

    // The ONLY way a webhook changes what a teacher is entitled to.
    //
    // One statement, so two webhooks arriving together cannot interleave a
    // read with a write: each sets its own rail's column and the derived
    // columns are recomputed from both in the same breath. A rail passing
    // 'trial' is revoking its own subscription, which leaves the other
    // rail's untouched and still winning.
    await sql`
      create or replace function public.apply_entitlement(p_teacher text, p_rail text, p_plan text)
      returns table (plan text, plan_source text, plan_revenuecat text, plan_stripe text)
      language plpgsql security definer set search_path = public as $fn$
      begin
        if p_rail not in ('revenuecat', 'stripe') then
          raise exception 'unknown billing rail: %', p_rail;
        end if;
        insert into public.profiles (teacher_id) values (p_teacher)
          on conflict (teacher_id) do nothing;
        return query
        update public.profiles p
           set plan_revenuecat = r.rc,
               plan_stripe     = r.st,
               plan            = public.best_plan(r.rc, r.st),
               plan_source     = public.best_plan_rail(r.rc, r.st),
               updated_at      = now()
          from (
            select
              case when p_rail = 'revenuecat' then nullif(p_plan, '') else q.plan_revenuecat end as rc,
              case when p_rail = 'stripe'     then nullif(p_plan, '') else q.plan_stripe     end as st
            from public.profiles q where q.teacher_id = p_teacher
          ) r
         where p.teacher_id = p_teacher
        returning p.plan, p.plan_source, p.plan_revenuecat, p.plan_stripe;
      end
      $fn$`;
    // Recompute the derived columns for everyone the backfill just touched,
    // so plan_source is populated before the app starts reading it.
    await sql`update public.profiles
                 set plan        = public.best_plan(plan_revenuecat, plan_stripe),
                     plan_source = public.best_plan_rail(plan_revenuecat, plan_stripe)
               where plan_revenuecat is not null or plan_stripe is not null`;
    // Marking defaults picked in Settings follow the account.
    await sql`alter table public.profiles add column if not exists default_mode text`;
    await sql`alter table public.profiles add column if not exists default_harshness int`;
    await sql`alter table public.profiles add column if not exists referral_code text`;
    await sql`alter table public.profiles add column if not exists referred_by text`;
    await sql`alter table public.profiles add column if not exists referral_count int not null default 0`;
    await sql`create unique index if not exists profiles_referral_code_idx on public.profiles (referral_code)`;
    // paidReferralCount filters on referred_by, and get_usage calls it on
    // every app open. Without this it is a sequential scan of profiles per
    // open — the 2026-09-08 scaling test measured get_usage at p95 10.3s
    // with 50 teachers online while every indexed action held under 1.7s.
    await sql`create index if not exists profiles_referred_by_idx on public.profiles (referred_by) where referred_by is not null`;
    await sql.end();
    return Response.json({ ok: true });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
