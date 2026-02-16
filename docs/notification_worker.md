# Notification Worker (Edge Function)

## 1) Apply SQL migrations
Run in Supabase SQL Editor, in this order:

1. `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-16-notification-settings.sql`
2. `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-16-notification-queue-events.sql`
3. `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-16-notification-queue-conflict-hotfix.sql`
4. `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-16-push-tokens.sql`

## 2) Deploy edge function
From project root:

```bash
supabase functions deploy notification-worker --no-verify-jwt
```

## 3) Set secrets

```bash
supabase secrets set WORKER_SECRET="replace-with-strong-secret"
supabase secrets set RESEND_API_KEY="re_xxx"
supabase secrets set RESEND_FROM_EMAIL="Liga Zala <no-reply@your-domain.com>"
```

Notes:
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase runtime.
- If RESEND secrets are not set, email jobs will fail with explicit error.

## 4) Invoke manually

```bash
curl -X POST "https://<PROJECT_REF>.functions.supabase.co/notification-worker" \
  -H "Content-Type: application/json" \
  -H "x-worker-secret: replace-with-strong-secret" \
  -d '{"channels":["push","email"],"limit":50}'
```

Dry-run mode (does not mark jobs as sent/failed):

```bash
curl -X POST "https://<PROJECT_REF>.functions.supabase.co/notification-worker" \
  -H "Content-Type: application/json" \
  -H "x-worker-secret: replace-with-strong-secret" \
  -d '{"channels":["push","email"],"limit":20,"dry_run":true}'
```

## 5) Check queue state

```sql
select channel, kind, status, count(*) as cnt
from public.notification_queue
group by 1,2,3
order by 1,2,3;
```

```sql
select created_at, channel, kind, title, status, attempts, last_error
from public.notification_queue
order by created_at desc
limit 100;
```

## 6) Push token registration (from app/backend)
When you have Expo push token in app, call:

```sql
select public.upsert_my_push_token(
  p_expo_push_token => 'ExponentPushToken[xxxxxxxxxxxxxx]',
  p_device_id => 'ios-simulator-1',
  p_platform => 'ios'
);
```

To deactivate token:

```sql
select public.deactivate_my_push_token('ExponentPushToken[xxxxxxxxxxxxxx]');
```
