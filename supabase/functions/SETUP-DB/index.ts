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
    await sql.end();
    return Response.json({ ok: true });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
