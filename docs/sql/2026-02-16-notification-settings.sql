-- Server-side storage for profile notification settings
-- Apply in Supabase SQL Editor.

begin;

create table if not exists public.profile_notification_settings (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  push_tournament boolean not null default true,
  push_mvp boolean not null default true,
  email_enabled boolean not null default true,
  email_digest boolean not null default true,
  email_important boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.get_my_notification_settings()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
  v_row public.profile_notification_settings%rowtype;
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into v_row
  from public.profile_notification_settings s
  where s.profile_id = v_profile_id;

  if not found then
    return jsonb_build_object(
      'push_enabled', true,
      'push_tournament', true,
      'push_mvp', true,
      'email_enabled', true,
      'email_digest', true,
      'email_important', true
    );
  end if;

  return jsonb_build_object(
    'push_enabled', coalesce(v_row.push_enabled, true),
    'push_tournament', coalesce(v_row.push_tournament, true),
    'push_mvp', coalesce(v_row.push_mvp, true),
    'email_enabled', coalesce(v_row.email_enabled, true),
    'email_digest', coalesce(v_row.email_digest, true),
    'email_important', coalesce(v_row.email_important, true)
  );
end;
$$;

create or replace function public.upsert_my_notification_settings(
  p_push_enabled boolean,
  p_push_tournament boolean,
  p_push_mvp boolean,
  p_email_enabled boolean,
  p_email_digest boolean,
  p_email_important boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.profile_notification_settings (
    profile_id,
    push_enabled,
    push_tournament,
    push_mvp,
    email_enabled,
    email_digest,
    email_important
  )
  values (
    v_profile_id,
    coalesce(p_push_enabled, true),
    coalesce(p_push_tournament, true),
    coalesce(p_push_mvp, true),
    coalesce(p_email_enabled, true),
    coalesce(p_email_digest, true),
    coalesce(p_email_important, true)
  )
  on conflict (profile_id) do update
    set push_enabled = excluded.push_enabled,
        push_tournament = excluded.push_tournament,
        push_mvp = excluded.push_mvp,
        email_enabled = excluded.email_enabled,
        email_digest = excluded.email_digest,
        email_important = excluded.email_important,
        updated_at = now();
end;
$$;

grant execute on function public.get_my_notification_settings() to authenticated;
grant execute on function public.upsert_my_notification_settings(boolean, boolean, boolean, boolean, boolean, boolean) to authenticated;

commit;
