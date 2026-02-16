-- Push token storage for notification worker (Expo tokens)
-- Apply in Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

create table if not exists public.profile_push_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  expo_push_token text not null,
  device_id text,
  platform text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profile_push_tokens_unique_token
  on public.profile_push_tokens (expo_push_token);

create index if not exists profile_push_tokens_profile_idx
  on public.profile_push_tokens (profile_id, is_active);

create or replace function public.upsert_my_push_token(
  p_expo_push_token text,
  p_device_id text default null,
  p_platform text default null
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

  if trim(coalesce(p_expo_push_token, '')) = '' then
    raise exception 'Push token is required';
  end if;

  insert into public.profile_push_tokens (
    profile_id,
    expo_push_token,
    device_id,
    platform,
    is_active
  )
  values (
    v_profile_id,
    trim(p_expo_push_token),
    nullif(trim(coalesce(p_device_id, '')), ''),
    nullif(trim(coalesce(p_platform, '')), ''),
    true
  )
  on conflict (expo_push_token) do update
    set profile_id = excluded.profile_id,
        device_id = coalesce(excluded.device_id, public.profile_push_tokens.device_id),
        platform = coalesce(excluded.platform, public.profile_push_tokens.platform),
        is_active = true,
        updated_at = now();
end;
$$;

create or replace function public.deactivate_my_push_token(
  p_expo_push_token text
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

  update public.profile_push_tokens
     set is_active = false,
         updated_at = now()
   where profile_id = v_profile_id
     and expo_push_token = trim(coalesce(p_expo_push_token, ''));
end;
$$;

grant execute on function public.upsert_my_push_token(text, text, text) to authenticated;
grant execute on function public.deactivate_my_push_token(text) to authenticated;

commit;
