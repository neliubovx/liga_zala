-- Auto-run notification worker via pg_cron + pg_net
-- This job invokes edge function notification-worker every 2 minutes.
--
-- BEFORE running this script, make sure Vault secrets exist:
--   1) project_url    = https://svfiiceaadjuzdusxqek.supabase.co
--   2) worker_secret  = same value as WORKER_SECRET in edge function secrets
--
-- You can create them once with:
--   select vault.create_secret('https://svfiiceaadjuzdusxqek.supabase.co', 'project_url', 'Supabase project URL');
--   select vault.create_secret('<WORKER_SECRET>', 'worker_secret', 'Edge worker secret');

begin;

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Safety checks for required Vault secrets.
do $$
begin
  if not exists (
    select 1
    from vault.decrypted_secrets
    where name = 'project_url'
  ) then
    raise exception 'Vault secret "project_url" is missing';
  end if;

  if not exists (
    select 1
    from vault.decrypted_secrets
    where name = 'worker_secret'
  ) then
    raise exception 'Vault secret "worker_secret" is missing';
  end if;
end
$$;

-- Recreate job if already exists.
do $$
declare
  v_job record;
begin
  for v_job in
    select jobid
    from cron.job
    where jobname = 'notification-worker-every-2-min'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
end
$$;

-- Schedule every 2 minutes.
select cron.schedule(
  'notification-worker-every-2-min',
  '*/2 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/notification-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'worker_secret')
    ),
    body := '{"channels":["push","email"],"limit":100}'::jsonb,
    timeout_milliseconds := 10000
  ) as request_id;
  $$
);

commit;
