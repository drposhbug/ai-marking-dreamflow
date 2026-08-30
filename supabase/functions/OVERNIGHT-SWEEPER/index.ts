// supabase/functions/OVERNIGHT-SWEEPER/index.ts
//
// Finishes overnight marking runs that nobody is watching.
//
// The flagship promise is "scan the class set at 9pm, wake up to marked
// papers". Anthropic honours its half of that: the Batch API returns inside
// 24h and keeps the results retrievable for 29 days. Nothing on OUR side
// noticed. Until this function existed, a batch only ever became "ended" as
// a side effect of the teacher opening the app and MARKING-PROCESS's
// batch_status action polling it. Three things broke because of that:
//
//   1. The "your class set is marked" push had nothing to fire it. Results
//      landed when the teacher next opened the app, not when they finished.
//   2. The owner paid Anthropic for marking that usage_log never recorded.
//      batch_submit runs budgetGate but writes no row; the only grade_batch
//      row is written inside the poll path. A teacher who queued 30 papers
//      and never reopened the app cost real money that was invisible to
//      both the credit meter and the monthly spend cap.
//   3. A reinstall or a new phone lost the batch. The row and the results
//      both still existed; no client could find them.
//
// This runs on a schedule (pg_cron, every 15 minutes -- see
// docs/overnight-sweeper.md) and closes all three. It is deliberately a
// separate function: MARKING-PROCESS is request-scoped and business-critical,
// and this needs a cron, not another branch inside it.
//
// Secrets required (`npx supabase secrets set ...`):
//   ANTHROPIC_API_KEY          - same key that submitted the batches
//   SUPABASE_SERVICE_ROLE_KEY  - provided by the platform; also the shared
//                                secret the scheduler authenticates with
//   ONESIGNAL_APP_ID           - optional. Missing = no push, sweep still runs
//   ONESIGNAL_REST_API_KEY     - optional. Missing = no push, sweep still runs
//
// Getting the money right matters more than getting the notification out, so
// a missing OneSignal key is a no-op that still completes the sweep.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

function serviceDb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

// ---------- Metering ----------
//
// These MUST stay identical to MARKING-PROCESS/index.ts. Edge functions have
// no shared module in this project, so the constants are duplicated on
// purpose: a sweeper that prices tokens differently from the poll path would
// make the credit meter disagree with itself depending on which one happened
// to bill, which is worse than not sweeping at all. Change one, change both.
const PRICE_IN_PER_M = 3; // USD per 1M input tokens
const PRICE_OUT_PER_M = 15; // USD per 1M output tokens

// Anthropic keeps batch results retrievable for 29 days after creation, and
// a batch itself always finishes within 24h. Older rows can never be settled
// from the API, so scanning them just burns requests forever.
const RESULTS_RETRIEVABLE_DAYS = 29;

// One run has a wall-clock budget like any other request. Sweeping is
// idempotent and runs every 15 minutes, so a backlog drains over a few runs
// rather than timing out a single one and settling nothing.
const MAX_BATCHES_PER_RUN = 25;

/// Byte-for-byte the same write MARKING-PROCESS makes, including the
/// Math.round and the cost formula. The halving for the Batch API is folded
/// into the TOKEN counts by the caller (exactly as the poll path does), never
/// into the price, so a grade_batch row always means "billable-equivalent
/// tokens" whichever path wrote it.
async function logUsage(
  teacherId: string,
  action: string,
  inputTokens: number,
  outputTokens: number,
  priceInPerM: number = PRICE_IN_PER_M,
  priceOutPerM: number = PRICE_OUT_PER_M,
): Promise<void> {
  if (!teacherId) return;
  try {
    const { error } = await serviceDb().from("usage_log").insert({
      teacher_id: teacherId,
      action,
      input_tokens: Math.round(inputTokens),
      output_tokens: Math.round(outputTokens),
      cost_usd: (inputTokens * priceInPerM) / 1e6 + (outputTokens * priceOutPerM) / 1e6,
    });
    if (error) throw error;
  } catch (e) {
    console.error("usage_log write failed (run SETUP-DB?):", e instanceof Error ? e.message : e);
  }
}

// ---------- Push ----------
//
// Copy matches PushService.batchDoneCopy in the app, minus the class label:
// marking_batches has no column holding what the teacher called the set, and
// inventing one for a notification subtitle is not worth a migration.
async function notifyBatchDone(teacherId: string, papers: number): Promise<string> {
  const appId = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
  const restKey = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
  // No key configured is a legitimate deployment: push is optional and the
  // app falls back to in-app messages. Never let it fail the sweep.
  if (!appId || !restKey) return "skipped: no OneSignal key";
  try {
    const res = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "content-type": "application/json; charset=utf-8",
        authorization: `Key ${restKey}`,
      },
      body: JSON.stringify({
        app_id: appId,
        target_channel: "push",
        // The app calls OneSignal.login(teacherId) with the same id
        // Purchases.logIn uses, so external_id reaches this teacher on every
        // device they are signed in on -- and nobody else.
        include_aliases: { external_id: [teacherId] },
        headings: { en: "Your class set is marked" },
        contents: { en: `${papers} ${papers === 1 ? "paper" : "papers"} came back marked overnight.` },
        // Tapping it opens the dashboard, which is where the results are.
        data: { route: "/dashboard" },
      }),
    });
    if (!res.ok) return `onesignal ${res.status}: ${(await res.text()).slice(0, 200)}`;
    return "sent";
  } catch (e) {
    return "onesignal failed: " + (e instanceof Error ? e.message : String(e));
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  // Only the scheduler may run this. The anon key ships inside the APK and
  // passes the gateway's verify_jwt, so "it presented a valid JWT" is not a
  // check -- anything a teacher's phone can send, a teacher can send. The
  // service role key never leaves the server, and pg_cron already sends it.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const auth = (req.headers.get("authorization") ?? "").trim();
  if (!serviceKey || auth.replace(/^Bearer\s+/i, "") !== serviceKey) {
    return json({ error: "unauthorized" }, 401);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "Missing ANTHROPIC_API_KEY secret" }, 500);
  const anthropic = new Anthropic({ apiKey });
  const db = serviceDb();

  const since = new Date(Date.now() - RESULTS_RETRIEVABLE_DAYS * 86400_000).toISOString();
  const { data: rows, error: listErr } = await db
    .from("marking_batches")
    .select("batch_id, teacher_id, status, created_at")
    .neq("status", "ended")
    .gte("created_at", since)
    .order("created_at", { ascending: true })
    .limit(MAX_BATCHES_PER_RUN);
  if (listErr) return json({ error: listErr.message }, 500);

  let scanned = 0;
  let stillRunning = 0;
  let settled = 0;
  let billed = 0;
  const notes: string[] = [];

  for (const row of rows ?? []) {
    const batchId = String(row.batch_id ?? "");
    const teacherId = String(row.teacher_id ?? "");
    if (!batchId || !teacherId) continue;
    scanned++;
    // One bad batch must not cost the others their sweep. A single paper
    // that trips the results stream would otherwise strand every teacher
    // whose batch happens to sort after it.
    try {
      // deno-lint-ignore no-explicit-any
      const batch: any = await (anthropic as any).messages.batches.retrieve(batchId);
      if (String(batch?.processing_status ?? "") !== "ended") {
        stillRunning++;
        continue;
      }

      // Read the results BEFORE claiming the row. Claiming first would mean a
      // stream failure leaves the batch marked settled with nothing ever
      // logged against it -- an under-bill with no second chance, because
      // every later sweep would skip it.
      let spentIn = 0;
      let spentOut = 0;
      let papers = 0;
      // deno-lint-ignore no-explicit-any
      const stream: any = await (anthropic as any).messages.batches.results(batchId);
      for await (const entry of stream) {
        const result = entry?.result;
        if (result?.type !== "succeeded") continue;
        const usage = result.message?.usage ?? {};
        // Identical arithmetic to the poll path in MARKING-PROCESS: a cached
        // prefix read bills at 10%, and everything in a batch bills at half
        // price. Both discounts are applied to the token counts, so the row
        // lands on the same cost_usd whichever path got there first.
        spentIn += ((usage.input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0) * 0.1) * 0.5;
        spentOut += (usage.output_tokens ?? 0) * 0.5;
        papers++;
      }

      // The one statement that makes billing exactly-once. Two devices
      // polling at the same moment can both read "in_progress" and both call
      // logUsage; reading a status and then billing on what it said is a race
      // with real money in it. This is a conditional update: the database
      // decides who wins, and only the winner is allowed to bill. Losing is
      // normal and silent -- it means somebody else settled this batch first.
      const { data: won, error: claimErr } = await db
        .from("marking_batches")
        .update({ status: "ended", updated_at: new Date().toISOString() })
        .eq("batch_id", batchId)
        .neq("status", "ended")
        .select("batch_id");
      if (claimErr) throw claimErr;
      if (!won || won.length !== 1) {
        notes.push(`${batchId}: already settled elsewhere`);
        continue;
      }
      settled++;

      if (spentIn > 0 || spentOut > 0) {
        await logUsage(teacherId, "grade_batch", spentIn, spentOut);
        billed++;
      }

      // Notifications come last and can never undo any of the above. A
      // teacher finding out late is a disappointment; the owner paying for
      // marking that was never metered is a leak.
      if (papers > 0) {
        const sent = await notifyBatchDone(teacherId, papers);
        if (sent !== "sent") notes.push(`${batchId}: ${sent}`);
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`sweep failed for ${batchId}:`, msg);
      notes.push(`${batchId}: ${msg.slice(0, 200)}`);
    }
  }

  return json({ ok: true, scanned, stillRunning, settled, billed, notes });
});
