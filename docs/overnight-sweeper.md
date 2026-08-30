# OVERNIGHT-SWEEPER — deploy and runbook

> Status at the time of writing: **written, never deployed, never scheduled.**
> Nothing in this document has been run against the live project. Every step
> below is for the owner to run with real credentials.

## What it is

`supabase/functions/OVERNIGHT-SWEEPER/index.ts` is a scheduled function that
finishes overnight marking runs nobody is watching. It is meant to run every
15 minutes, and it is safe to run more or less often than that.

Each run:

1. Selects `marking_batches` rows where `status <> 'ended'` and
   `created_at > now() - 29 days` (Anthropic keeps batch results retrievable
   for 29 days; a batch itself always finishes within 24 hours, so anything
   older can never be settled from the API).
2. Calls `messages.batches.retrieve(batch_id)` and skips anything whose
   `processing_status` is not `ended`.
3. Streams the results and sums the billable tokens.
4. Claims the row with a conditional update, and bills only if it won.
5. Sends the "your class set is marked" push, last, where it cannot undo
   anything above.

## Why it exists

Overnight marking is the flagship feature: scan the class set at bedtime, wake
up to marked papers. Anthropic held up its end. We did not — until this
function, **nothing server-side ever finished a batch**. `status` only became
`ended` as a side effect of the app calling `batch_status`. Three consequences:

- **The push had nothing to fire it.** The server never learned a batch had
  ended, so the results landed when the teacher next *opened* the app, not
  when the marking finished. That is precisely the chore the feature exists
  to remove.
- **Money leaked, silently.** `batch_submit` runs `budgetGate` but writes no
  `usage_log` row. The only `grade_batch` billing lives inside the poll path.
  A teacher who queued thirty papers and never reopened the app meant
  Anthropic billed the owner and `usage_log` recorded nothing — invisible to
  the credit meter and to the monthly spend cap that guarantees the margin.
- **Batches were device-local.** Reinstall, or a new phone, and a night's
  marking was unreachable. The `marking_batches` row and the Anthropic
  results both still existed; no client could discover them. The additive
  `list_batches` action in `MARKING-PROCESS` fixes that half.

## Billing is exactly-once

This is the part worth reading carefully.

The old guard read `marking_batches.status`, and *then* billed if it had said
`in_progress`. Two devices polling the same batch at the same moment could
both read `in_progress` and both call `logUsage` — a time-of-check to
time-of-use race with real money in it.

The sweeper never bills on the strength of a value it read. It bills on the
strength of a row it changed:

```sql
UPDATE marking_batches
   SET status = 'ended', updated_at = now()
 WHERE batch_id = $1
   AND status <> 'ended'
```

The database decides the winner. Exactly one caller sees one row changed;
everyone else sees zero and bills nothing. Losing is normal and silent.

Two ordering details that follow from that:

- Results are **streamed before** the claim. Claiming first would mean a
  stream failure leaves the batch marked settled with nothing logged against
  it — an under-bill with no second chance, since every later sweep skips it.
- Usage is logged **after** the claim, and the notification is sent after
  that. A teacher finding out late is a disappointment; the owner paying for
  marking that was never metered is a leak.

The token arithmetic is copied verbatim from the poll path in
`MARKING-PROCESS`, and must stay that way:

```
spentIn  += (input_tokens + cache_read_input_tokens * 0.1) * 0.5
spentOut += (output_tokens) * 0.5
```

Both discounts (10% for a cached prefix read, 50% for the Batch API) are
applied to the **token counts**, not to the price, so the resulting
`cost_usd` is identical no matter which path settled the batch. `logUsage`,
`PRICE_IN_PER_M = 3` and `PRICE_OUT_PER_M = 15` are duplicated in the sweeper
because these edge functions share no module. **Change one, change both** — a
sweeper that prices tokens differently from the poll path would make the
credit meter disagree with itself depending on which one happened to bill.

## Secrets

Set with `npx supabase secrets set NAME=value --project-ref zxikjizraeqejbsncqpg`.

| Secret | Required | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | yes | The same key that submitted the batches. Already set for `MARKING-PROCESS`; secrets are project-wide, so nothing new to do. |
| `SUPABASE_URL` | provided | Set by the platform. |
| `SUPABASE_SERVICE_ROLE_KEY` | provided | Set by the platform. Also the shared secret the scheduler authenticates with — see below. |
| `ONESIGNAL_APP_ID` | no | OneSignal app id. Missing means no push; the sweep still runs and still bills. |
| `ONESIGNAL_REST_API_KEY` | no | OneSignal REST API key. Missing means no push; the sweep still runs and still bills. |

Billing correctness deliberately does not depend on notifications working.

### Who is allowed to call it

The function refuses anything that does not present the service role key in
`Authorization`. This is not paranoia: the anon key ships inside the APK and
passes the gateway's `verify_jwt`, so "it presented a valid JWT" is not a
check — anything a teacher's phone can send, a teacher can send. Deploy it
normally (**not** `--no-verify-jwt`); the cron job already sends the service
role key.

## Deploy

The project's established invocation (same as `MARKING-PROCESS`):

```bash
npx supabase functions deploy OVERNIGHT-SWEEPER --project-ref zxikjizraeqejbsncqpg
```

The Docker warning is benign — the CLI uses the API bundler. Deno is not
installed locally, so this deploy is also the first time the function is
type-checked.

`MARKING-PROCESS` gained a `list_batches` action in the same change, so
redeploy it too:

```bash
npx supabase functions deploy MARKING-PROCESS --project-ref zxikjizraeqejbsncqpg
```

No schema change is needed. `SETUP-DB` does not have to be re-run: the
sweeper uses only columns that already exist (`marking_batches.batch_id`,
`teacher_id`, `status`, `meta`, `created_at`, `updated_at`, and `usage_log`'s
`teacher_id`, `action`, `input_tokens`, `output_tokens`, `cost_usd`).

## Schedule it with pg_cron

Run all of this in the Supabase SQL editor.

**1. Enable the extensions.**

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;
```

**2. Store the service role key in Vault**, so it is not sitting in readable
plaintext inside `cron.job.command`. Get the key with
`npx supabase projects api-keys --project-ref zxikjizraeqejbsncqpg -o json`
(the `service_role` row).

```sql
select vault.create_secret(
  'PASTE_SERVICE_ROLE_KEY_HERE',
  'sweeper_service_key',
  'Service role key the overnight sweeper cron authenticates with'
);
```

**3. Schedule the job at 15-minute intervals.**

```sql
select cron.schedule(
  'overnight-sweeper',
  '*/15 * * * *',
  $$
  select net.http_post(
    url     := 'https://zxikjizraeqejbsncqpg.supabase.co/functions/v1/OVERNIGHT-SWEEPER',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets
         where name = 'sweeper_service_key'
      )
    ),
    body    := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $$
);
```

To change the schedule later, call `cron.schedule` again with the same job
name — it replaces the existing job. To stop it:
`select cron.unschedule('overnight-sweeper');`

Fifteen minutes is a deliberate choice, not a tuning knob: a batch usually
finishes well inside an hour, and the teacher is asleep. Waking a phone the
instant a batch lands is worth nothing; billing it before the month closes is
worth everything. Each run settles at most 25 batches — a backlog drains over
a few runs instead of timing out one run and settling nothing.

## Verify it works, end to end

**1. The function answers.** Should return `{"ok":true, ...}`:

```bash
curl -X POST https://zxikjizraeqejbsncqpg.supabase.co/functions/v1/OVERNIGHT-SWEEPER \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" -d '{}'
```

The body reports `scanned`, `stillRunning`, `settled`, `billed` and a `notes`
array of per-batch problems. On a quiet project all the counters are zero and
that is a pass.

**2. Rejects an unauthorized caller.** The same curl with the **anon** key
must return `401 {"error":"unauthorized"}`. If it returns `ok:true`, stop and
fix it — every teacher has that key.

**3. The cron job is registered and running.**

```sql
select jobid, jobname, schedule, active from cron.job where jobname = 'overnight-sweeper';

select status, return_message, start_time, end_time
  from cron.job_run_details
 where jobid = (select jobid from cron.job where jobname = 'overnight-sweeper')
 order by start_time desc
 limit 10;
```

Expect `status = 'succeeded'` rows about four times an hour.

**4. The real test — a batch nobody polls.** Queue an overnight batch from
the app, then **force-quit the app and leave it closed.** Note the
`batch_id`. Within about 15 minutes of Anthropic finishing:

```sql
select batch_id, status, created_at, updated_at
  from marking_batches
 where batch_id = 'msgbatch_...';
```

`status` must read `ended`, with `updated_at` later than `created_at`, and
**no client ever having called `batch_status`**. That single row is the whole
feature working.

**5. The push arrives.** With `ONESIGNAL_APP_ID` and
`ONESIGNAL_REST_API_KEY` set and the phone signed in, "Your class set is
marked" should arrive and open the dashboard. If it does not, check the
`notes` array in the function's response and the OneSignal delivery log — but
note that steps 4 and 6 must still pass regardless. Push failing is a product
problem; billing failing is a money problem, and they are kept separate.

## Confirming the money leak is closed

This is the check that matters most, and it is worth running deliberately
rather than assuming.

Do step 4 above — queue a batch, force-quit the app, never reopen it. Then:

```sql
select id, teacher_id, action, input_tokens, output_tokens, cost_usd, created_at
  from usage_log
 where action = 'grade_batch'
 order by created_at desc
 limit 5;
```

**What a correct row looks like for an unpolled batch:**

- `action` is exactly `grade_batch` — the same string the poll path writes,
  so `get_usage` and `admin_stats` group it with everything else.
- `teacher_id` is the teacher who queued the batch (`marking_batches.teacher_id`),
  not the caller of anything.
- `input_tokens` and `output_tokens` are **already discounted**: halved for
  the Batch API, with cached prefix reads counted at 10%. They are
  billable-equivalent tokens, not raw usage numbers. A 30-paper set typically
  lands in the low tens of thousands of input tokens.
- `cost_usd` equals `input_tokens * 3 / 1e6 + output_tokens * 15 / 1e6`, and
  works out around **$0.008 per paper** — roughly $0.24 for a class of 30.
  Anything near the live-marking figure of $0.039/paper means the ×0.5 batch
  discount was not applied and the two paths have drifted apart.
- `created_at` is within about 15 minutes of the batch ending — *before* the
  teacher next opens the app, which is the entire point.

**Exactly one row per batch.** Reopen the app afterwards and let it poll the
same batch: `batch_status` sees the stored status is already `ended`, skips
`logUsage`, and returns the results. Re-run the sweeper by hand as many times
as you like; the conditional update loses every time after the first. Then
confirm the totals line up:

```sql
select
  (select count(*) from marking_batches
    where status = 'ended' and updated_at > now() - interval '1 day') as batches_ended,
  (select count(*) from usage_log
    where action = 'grade_batch' and created_at > now() - interval '1 day') as batches_billed;
```

These should match. `batches_billed` being **lower** means marking was paid
for and not metered — the leak is back. Higher means something billed twice.

Finally, the credit meter should move for a teacher who never opened the app:
their spend in `get_usage` (and the monthly cap in `budgetGate`) now includes
the overnight set, which is what makes the margin rule hold.

## Known gaps, deliberately left

- **A narrow race remains inside `batch_status`.** That action still reads
  `row.status`, then streams results, then bills — so a sweep landing inside
  that window could still let both paths bill the same batch. In practice the
  sweeper settles batches long before a teacher opens the app, so the window
  is small; closing it fully means giving `batch_status` the same conditional
  update the sweeper uses. Left alone here on purpose: this change is
  additive to `MARKING-PROCESS`, and that is a change to its billing path.
- **The push has no class label.** `marking_batches` holds no column naming
  the set ("Year 9 Physics"), so the notification body is the paper count
  only. The app's `batchDoneCopy` has a `label` slot; filling it server-side
  would need a new column, which is not worth a migration for a subtitle.
- **The per-teacher "batch done" toggle is not enforced server-side.** The
  preference lives on the device and is mirrored to OneSignal as the
  `notify_batch_done` tag; this send targets `include_aliases.external_id`,
  which cannot be combined with a tag filter. Enforcing it here would need
  either an OneSignal-side rule or a push-preferences column on `profiles`
  that does not exist today.
- **A batch id Anthropic no longer recognises is retried** every run until it
  falls out of the 29-day window. It is logged in `notes` and costs one
  failed retrieve per run. Nothing is billed for it, because there is nothing
  to read.
