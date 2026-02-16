-- Hall roles + secure admin actions + RLS for hall_members
-- Apply in Supabase SQL Editor.

begin;

alter table public.hall_members
  add column if not exists role text;

update public.hall_members
set role = lower(trim(coalesce(role, '')))
where role is not null;

update public.hall_members
set role = 'player'
where role is null
   or role = ''
   or role not in ('owner', 'admin', 'player');

alter table public.hall_members
  alter column role set default 'player';

alter table public.hall_members
  alter column role set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    where c.conname = 'hall_members_role_check'
      and c.conrelid = 'public.hall_members'::regclass
  ) then
    alter table public.hall_members
      add constraint hall_members_role_check
      check (role in ('owner', 'admin', 'player'));
  end if;
end
$$;

create or replace function public.assert_hall_admin(
  p_hall_id uuid,
  p_profile_id uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_role text;
begin
  if p_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  select lower(coalesce(hm.status, '')),
         lower(coalesce(hm.role, 'player'))
    into v_status, v_role
  from public.hall_members hm
  where hm.hall_id = p_hall_id
    and hm.profile_id = p_profile_id
  limit 1;

  if v_status <> 'approved' or v_role not in ('owner', 'admin') then
    raise exception 'Only hall admins can perform this action';
  end if;
end;
$$;

create or replace function public.get_my_hall_membership(
  p_hall_id uuid
)
returns table (
  hall_id uuid,
  profile_id uuid,
  role text,
  status text,
  is_owner boolean,
  is_admin boolean
)
language sql
security definer
set search_path = public
as $$
  select
    hm.hall_id,
    hm.profile_id,
    lower(coalesce(hm.role, 'player')) as role,
    lower(coalesce(hm.status, '')) as status,
    lower(coalesce(hm.role, 'player')) = 'owner' as is_owner,
    (
      lower(coalesce(hm.status, '')) = 'approved'
      and lower(coalesce(hm.role, 'player')) in ('owner', 'admin')
    ) as is_admin
  from public.hall_members hm
  where hm.hall_id = p_hall_id
    and hm.profile_id = auth.uid()
  limit 1;
$$;

create or replace function public.get_hall_pending_requests(
  p_hall_id uuid
)
returns table (
  profile_id uuid,
  display_name text,
  email text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_hall_admin(p_hall_id);

  return query
  select
    hm.profile_id,
    coalesce(
      nullif(trim(pr.display_name), ''),
      nullif(trim(pr.email), ''),
      'Пользователь'
    ) as display_name,
    pr.email
  from public.hall_members hm
  left join public.profiles pr
    on pr.id = hm.profile_id
  where hm.hall_id = p_hall_id
    and lower(coalesce(hm.status, '')) = 'pending'
  order by lower(
    coalesce(
      nullif(trim(pr.display_name), ''),
      nullif(trim(pr.email), ''),
      'пользователь'
    )
  );
end;
$$;

create or replace function public.approve_hall_member_request(
  p_hall_id uuid,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_hall_admin(p_hall_id);

  update public.hall_members hm
     set status = 'approved',
         role = lower(coalesce(hm.role, 'player'))
   where hm.hall_id = p_hall_id
     and hm.profile_id = p_profile_id;

  if not found then
    raise exception 'Request not found';
  end if;
end;
$$;

create or replace function public.reject_hall_member_request(
  p_hall_id uuid,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_hall_admin(p_hall_id);

  delete from public.hall_members hm
  where hm.hall_id = p_hall_id
    and hm.profile_id = p_profile_id
    and lower(coalesce(hm.status, '')) = 'pending';

  if not found then
    raise exception 'Request not found';
  end if;
end;
$$;

create or replace function public.set_hall_member_role(
  p_hall_id uuid,
  p_profile_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  if v_role not in ('admin', 'player') then
    raise exception 'Role must be admin or player';
  end if;

  if not exists (
    select 1
    from public.hall_members hm
    where hm.hall_id = p_hall_id
      and hm.profile_id = v_actor
      and lower(coalesce(hm.status, '')) = 'approved'
      and lower(coalesce(hm.role, 'player')) = 'owner'
  ) then
    raise exception 'Only hall owner can change roles';
  end if;

  update public.hall_members hm
     set role = v_role
   where hm.hall_id = p_hall_id
     and hm.profile_id = p_profile_id
     and lower(coalesce(hm.status, '')) = 'approved'
     and lower(coalesce(hm.role, 'player')) <> 'owner';

  if not found then
    raise exception 'Member not found or owner role is protected';
  end if;
end;
$$;

grant execute on function public.assert_hall_admin(uuid, uuid) to authenticated;
grant execute on function public.get_my_hall_membership(uuid) to authenticated;
grant execute on function public.get_hall_pending_requests(uuid) to authenticated;
grant execute on function public.approve_hall_member_request(uuid, uuid) to authenticated;
grant execute on function public.reject_hall_member_request(uuid, uuid) to authenticated;
grant execute on function public.set_hall_member_role(uuid, uuid, text) to authenticated;

alter table public.hall_members enable row level security;

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'hall_members'
      and policyname = 'hall_members_select_own'
  ) then
    execute 'drop policy hall_members_select_own on public.hall_members';
  end if;
end
$$;

create policy hall_members_select_own
on public.hall_members
for select
to authenticated
using (profile_id = auth.uid());

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'hall_members'
      and policyname = 'hall_members_insert_self_pending'
  ) then
    execute 'drop policy hall_members_insert_self_pending on public.hall_members';
  end if;
end
$$;

create policy hall_members_insert_self_pending
on public.hall_members
for insert
to authenticated
with check (
  profile_id = auth.uid()
  and lower(coalesce(status, 'pending')) = 'pending'
  and lower(coalesce(role, 'player')) = 'player'
);

commit;
