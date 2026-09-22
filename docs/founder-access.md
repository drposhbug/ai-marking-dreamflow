# Founder access — your own account, with room to test everything

There is no admin login screen and no admin password. Teachers create accounts
and sign in with Google exactly as before; **your** account is recognised by the
server and given the `preview` allowance automatically.

A password would have been the wrong shape. Anything the app can check, a
teacher can read out of `main.dart.js` — the web bundle ships to the browser —
so an in-app admin password protects nothing. The entitlement is decided by the
edge function instead, where the client cannot reach it.

## What you get

`preview` is deliberately more generous than Pro, because testing burns credits
that no one is paying for:

| | monthly marking budget | plans/month | mark on the spot |
|---|---|---|---|
| Free trial | $0.40 | 5 | no |
| Pro | $3.55 | 30 | yes |
| **Preview (you)** | **$10.00** | **30** | **yes** |

Planning is unlocked without needing a referral. Everything else behaves exactly
as it does for a paying teacher, which is the point — you are testing the real
product, not a special mode.

If you ever actually subscribe, the real subscription wins over `preview`. That
is deliberate: founder access must not be able to hide a billing bug.

## Setting it up

The default is already your address, so signing in with Google as
`oscar.cs.lee@gmail.com` is enough. To add or change accounts without a deploy:

```bash
npx supabase secrets set FOUNDER_EMAILS=you@example.com,colleague@example.com
```

Better, once the account exists — an account id is the JWT's subject and cannot
be claimed by anyone else, so it needs no lookup against Auth:

```bash
npx supabase secrets set FOUNDER_TEACHER_IDS=<your auth user id>
```

Then deploy the function that reads them:

```bash
npx supabase functions deploy MARKING-PROCESS
```

**Until that deploy lands, none of this is live** — including the fixes below.

## How the check is made, and the hole it closes

`profiles.email` is **not** evidence of who you are. It is a display field, and
`save_profile` used to write whatever the client sent:

```ts
if (payload?.email != null) row.email = String(payload.email).slice(0, 200);
```

Since the founder check matched that column, any teacher could set their profile
email to the founder's address and take the preview allowance — nearly three
times Pro's marking budget — plus Planning. The referral action was worse: it
matched the address **straight out of the request body**, so unlocking Planning
needed no database write at all, just a field in a POST.

Both are now closed:

1. **`save_profile` no longer accepts an email.** It writes the address from the
   verified JWT claim. The gateway checks the token's signature and
   `requireTeacher` pins its subject to the account being written, so the stored
   address is the account's real one.
2. **`isFounder` confirms a claim against Supabase Auth**, the only thing that
   can write an account's true address. The cheap string compare runs first and
   rejects everyone not claiming to be a founder, so the admin lookup only runs
   for someone who is. It fails closed: an account that cannot be confirmed is
   not a founder.

Both layers are kept on purpose. (1) alone would be enough while it holds, but
(2) means a future endpoint that writes `profiles.email` cannot quietly reopen
the same hole.

## Checking it worked

Sign in, open **Plans**. The current-plan card reads **Preview**. On the grading
screen, *Mark now* is available rather than pointing you at overnight — that
flag comes from the server's usage payload, so seeing it is proof the server
agreed you are a founder, not a client-side guess.
