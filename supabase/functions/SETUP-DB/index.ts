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
    await sql.end();
    return Response.json({ ok: true });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
