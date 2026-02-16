# Notification Worker (Edge Function)

## Что это и зачем
- `notification-worker` это Edge Function, которая забирает задания из `notification_queue`, отправляет уведомления и помечает результат.
- Ручной `curl` нужен только для проверки.
- Для боевого режима включается расписание (`pg_cron`) и воркер запускается сам каждые 2 минуты.

## 1) Apply base SQL migrations
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

## 4) Save values in Vault (for cron job)
Run in Supabase SQL Editor:

```sql
select vault.create_secret('https://<PROJECT_REF>.supabase.co', 'project_url', 'Supabase project URL');
select vault.create_secret('<WORKER_SECRET>', 'worker_secret', 'Edge worker secret');
```

If the secret already exists, skip this step.

## 5) Enable auto-run (no manual curl)
Run:

1. `/Users/neliubove/dev/liga_zala/docs/sql/2026-02-16-notification-worker-cron.sql`

It creates cron job `notification-worker-every-2-min` and calls edge function every 2 minutes.

## 6) Verify cron + queue
Check cron job exists:

```sql
select jobid, jobname, schedule, active
from cron.job
where jobname = 'notification-worker-every-2-min';
```

Check last HTTP calls from cron:

```sql
select id, status_code, error_msg, created
from net._http_response
order by created desc
limit 20;
```

Check queue states:

```sql
select channel, kind, status, count(*) as cnt
from public.notification_queue
group by 1,2,3
order by 1,2,3;
```

## 7) Optional manual invoke (debug only)

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

## 8) Push token registration (from app/backend)
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
