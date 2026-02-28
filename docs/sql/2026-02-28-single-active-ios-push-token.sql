-- Keep only one active iOS push token per profile.
-- Apply in Supabase SQL Editor.

begin;

-- 1) Normalize existing data: for each profile keep newest active iOS token,
--    deactivate the rest so unique index can be created safely.
with ranked_ios as (
  select
    t.id,
    row_number() over (
      partition by t.profile_id
      order by t.updated_at desc nulls last, t.created_at desc nulls last, t.id desc
    ) as rn
  from public.profile_push_tokens t
  where t.is_active = true
    and lower(coalesce(t.platform, '')) = 'ios'
)
update public.profile_push_tokens t
set
  is_active = false,
  updated_at = now()
from ranked_ios r
where t.id = r.id
  and r.rn > 1;

-- 2) Hard guarantee at DB level: only one active iOS token per profile.
create unique index if not exists profile_push_tokens_one_active_ios_per_profile
  on public.profile_push_tokens (profile_id)
  where is_active = true
    and lower(coalesce(platform, '')) = 'ios';

-- 3) Update token upsert logic: when active token is iOS, deactivate older iOS tokens.
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
  v_token text := trim(coalesce(p_expo_push_token, ''));
  v_platform text := nullif(lower(trim(coalesce(p_platform, ''))), '');
  v_effective_platform text;
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_token = '' then
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
    v_token,
    nullif(trim(coalesce(p_device_id, '')), ''),
    v_platform,
    true
  )
  on conflict (expo_push_token) do update
    set profile_id = excluded.profile_id,
        device_id = coalesce(excluded.device_id, public.profile_push_tokens.device_id),
        platform = coalesce(excluded.platform, public.profile_push_tokens.platform),
        is_active = true,
        updated_at = now();

  select lower(coalesce(t.platform, ''))
    into v_effective_platform
  from public.profile_push_tokens t
  where t.profile_id = v_profile_id
    and t.expo_push_token = v_token
  limit 1;

  if v_effective_platform = 'ios' then
    update public.profile_push_tokens t
    set
      is_active = false,
      updated_at = now()
    where t.profile_id = v_profile_id
      and t.expo_push_token <> v_token
      and t.is_active = true
      and lower(coalesce(t.platform, '')) = 'ios';
  end if;
end;
$$;

grant execute on function public.upsert_my_push_token(text, text, text) to authenticated;

commit;
