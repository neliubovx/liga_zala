-- Notification queue + tournament/MVP event hooks
-- Apply AFTER:
--  1) 2026-02-15-mvp-voting.sql
--  2) 2026-02-16-mvp-profile-links.sql
--  3) 2026-02-16-notification-settings.sql

begin;

create extension if not exists pgcrypto;

create table if not exists public.notification_queue (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  hall_id uuid not null references public.halls(id) on delete cascade,
  tournament_id uuid references public.tournaments(id) on delete cascade,
  channel text not null,
  kind text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempts int not null default 0,
  last_error text,
  scheduled_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

-- Ensure allowed values even if table existed before this migration.
do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'notification_queue'
      and c.conname = 'notification_queue_channel_check'
  ) then
    alter table public.notification_queue
      add constraint notification_queue_channel_check
      check (channel in ('push', 'email'));
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'notification_queue'
      and c.conname = 'notification_queue_status_check'
  ) then
    alter table public.notification_queue
      add constraint notification_queue_status_check
      check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled'));
  end if;
end
$$;

create unique index if not exists notification_queue_unique_profile_tournament_kind_channel
  on public.notification_queue (profile_id, tournament_id, kind, channel);

create index if not exists notification_queue_status_scheduled_idx
  on public.notification_queue (status, scheduled_at, created_at);

create index if not exists notification_queue_profile_created_idx
  on public.notification_queue (profile_id, created_at desc);

create index if not exists notification_queue_hall_created_idx
  on public.notification_queue (hall_id, created_at desc);

create or replace function public.enqueue_profile_notification(
  p_profile_id uuid,
  p_hall_id uuid,
  p_tournament_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.profile_notification_settings%rowtype;
  v_has_settings boolean := false;
  v_push_allowed boolean := true;
  v_email_allowed boolean := true;
  v_push_enabled boolean := true;
  v_email_enabled boolean := true;
begin
  if p_profile_id is null or p_hall_id is null then
    return;
  end if;

  select *
    into v_settings
  from public.profile_notification_settings s
  where s.profile_id = p_profile_id;

  v_has_settings := found;

  if v_has_settings then
    v_push_enabled := coalesce(v_settings.push_enabled, true);
    v_email_enabled := coalesce(v_settings.email_enabled, true);
  end if;

  if p_kind = 'tournament_completed' then
    v_push_allowed := v_push_enabled and (
      not v_has_settings or coalesce(v_settings.push_tournament, true)
    );
    v_email_allowed := v_email_enabled and (
      not v_has_settings or coalesce(v_settings.email_digest, true)
    );
  elsif p_kind in ('mvp_voting_open', 'mvp_result') then
    v_push_allowed := v_push_enabled and (
      not v_has_settings or coalesce(v_settings.push_mvp, true)
    );
    v_email_allowed := v_email_enabled and (
      not v_has_settings or coalesce(v_settings.email_important, true)
    );
  else
    v_push_allowed := v_push_enabled;
    v_email_allowed := v_email_enabled;
  end if;

  if v_push_allowed then
    insert into public.notification_queue (
      profile_id,
      hall_id,
      tournament_id,
      channel,
      kind,
      title,
      body,
      payload
    )
    values (
      p_profile_id,
      p_hall_id,
      p_tournament_id,
      'push',
      p_kind,
      p_title,
      p_body,
      coalesce(p_payload, '{}'::jsonb)
    )
    on conflict (profile_id, tournament_id, kind, channel) do nothing;
  end if;

  if v_email_allowed then
    insert into public.notification_queue (
      profile_id,
      hall_id,
      tournament_id,
      channel,
      kind,
      title,
      body,
      payload
    )
    values (
      p_profile_id,
      p_hall_id,
      p_tournament_id,
      'email',
      p_kind,
      p_title,
      p_body,
      coalesce(p_payload, '{}'::jsonb)
    )
    on conflict (profile_id, tournament_id, kind, channel) do nothing;
  end if;
end;
$$;

create or replace function public.enqueue_hall_notification(
  p_hall_id uuid,
  p_tournament_id uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_payload jsonb default '{}'::jsonb,
  p_only_participants boolean default false
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member record;
  v_count int := 0;
begin
  if p_hall_id is null then
    return 0;
  end if;

  for v_member in
    select hm.profile_id
    from public.hall_members hm
    where hm.hall_id = p_hall_id
      and hm.status = 'approved'
      and (
        p_only_participants = false
        or (
          p_tournament_id is not null
          and exists (
            select 1
            from public.player_profile_links ppl
            join public.team_players tp
              on tp.player_id = ppl.player_id
             and tp.tournament_id = p_tournament_id
            where ppl.hall_id = p_hall_id
              and ppl.profile_id = hm.profile_id
          )
        )
      )
  loop
    perform public.enqueue_profile_notification(
      v_member.profile_id,
      p_hall_id,
      p_tournament_id,
      p_kind,
      p_title,
      p_body,
      p_payload
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function public.tg_enqueue_tournament_completed_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb;
begin
  if coalesce(new.completed, false)
     and (tg_op = 'INSERT' or coalesce(old.completed, false) = false) then

    v_payload := jsonb_build_object(
      'hall_id', new.hall_id,
      'tournament_id', new.id,
      'date', new.date
    );

    perform public.enqueue_hall_notification(
      new.hall_id,
      new.id,
      'tournament_completed',
      'Турнир завершён',
      'Турнир завершён. Открой приложение и проверь результаты.',
      v_payload,
      false
    );

    if new.mvp_voting_ends_at is not null
       and now() < new.mvp_voting_ends_at then
      perform public.enqueue_hall_notification(
        new.hall_id,
        new.id,
        'mvp_voting_open',
        'Открыто голосование MVP',
        'Голосование MVP открыто на 12 часов. Успей проголосовать.',
        v_payload || jsonb_build_object('voting_ends_at', new.mvp_voting_ends_at),
        true
      );
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.tg_enqueue_mvp_finalized_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_winner_name text;
  v_body text;
  v_payload jsonb;
begin
  if coalesce(new.mvp_votes_finalized, false)
     and (tg_op = 'INSERT' or coalesce(old.mvp_votes_finalized, false) = false) then

    if new.mvp_winner_player_id is not null then
      select p.name
        into v_winner_name
      from public.players p
      where p.id = new.mvp_winner_player_id;
    end if;

    v_body := case
      when new.mvp_winner_player_id is null
        then 'Голосование MVP завершено. Победитель не определён.'
      else format('Голосование MVP завершено. Победитель: %s.', coalesce(v_winner_name, 'Игрок'))
    end;

    v_payload := jsonb_build_object(
      'hall_id', new.hall_id,
      'tournament_id', new.id,
      'winner_player_id', new.mvp_winner_player_id
    );

    perform public.enqueue_hall_notification(
      new.hall_id,
      new.id,
      'mvp_result',
      'Итоги MVP готовы',
      v_body,
      v_payload,
      true
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enqueue_tournament_completed_notifications on public.tournaments;

create trigger trg_enqueue_tournament_completed_notifications
after insert or update of completed on public.tournaments
for each row
execute function public.tg_enqueue_tournament_completed_notifications();

drop trigger if exists trg_enqueue_mvp_finalized_notifications on public.tournaments;

create trigger trg_enqueue_mvp_finalized_notifications
after insert or update of mvp_votes_finalized on public.tournaments
for each row
execute function public.tg_enqueue_mvp_finalized_notifications();

-- Worker helpers (for Edge Function / backend sender)
create or replace function public.claim_notification_queue_jobs(
  p_channel text,
  p_limit int default 50
)
returns setof public.notification_queue
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit int;
begin
  v_limit := greatest(1, least(coalesce(p_limit, 50), 500));

  return query
  with picked as (
    select q.id
    from public.notification_queue q
    where q.status = 'pending'
      and q.channel = p_channel
      and q.scheduled_at <= now()
    order by q.created_at
    for update skip locked
    limit v_limit
  ),
  upd as (
    update public.notification_queue q
       set status = 'processing',
           attempts = q.attempts + 1
     where q.id in (select p.id from picked p)
     returning q.*
  )
  select * from upd;
end;
$$;

create or replace function public.mark_notification_queue_job(
  p_id uuid,
  p_success boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_id is null then
    return;
  end if;

  if coalesce(p_success, false) then
    update public.notification_queue q
       set status = 'sent',
           sent_at = now(),
           last_error = null
     where q.id = p_id;
  else
    update public.notification_queue q
       set status = 'failed',
           last_error = left(coalesce(p_error, 'unknown error'), 1000)
     where q.id = p_id;
  end if;
end;
$$;

revoke all on function public.enqueue_hall_notification(uuid, uuid, text, text, text, jsonb, boolean) from public, anon, authenticated;
revoke all on function public.enqueue_profile_notification(uuid, uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.claim_notification_queue_jobs(text, int) from public, anon, authenticated;
revoke all on function public.mark_notification_queue_job(uuid, boolean, text) from public, anon, authenticated;

grant execute on function public.claim_notification_queue_jobs(text, int) to service_role;
grant execute on function public.mark_notification_queue_job(uuid, boolean, text) to service_role;

commit;
