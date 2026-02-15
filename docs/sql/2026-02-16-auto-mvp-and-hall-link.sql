-- Auto-open MVP voting when tournament is completed
-- + account binding from Players tab (hall-level)
-- Apply AFTER:
--  1) 2026-02-15-mvp-voting.sql
--  2) 2026-02-16-mvp-profile-links.sql

begin;

-- Backfill hall_id for legacy players that participated in exactly one hall.
with inferred as (
  select
    tp.player_id,
    (array_agg(distinct t.hall_id::text order by t.hall_id::text))[1]::uuid as hall_id,
    count(distinct t.hall_id) as hall_count
  from public.team_players tp
  join public.tournaments t on t.id = tp.tournament_id
  group by tp.player_id
)
update public.players p
set hall_id = i.hall_id
from inferred i
where p.id = i.player_id
  and p.hall_id is null
  and i.hall_count = 1;

create or replace function public.link_my_profile_to_hall_player(
  p_hall_id uuid,
  p_player_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
  v_member_status text;
  v_player_belongs_to_hall boolean;
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  select hm.status
    into v_member_status
  from public.hall_members hm
  where hm.hall_id = p_hall_id
    and hm.profile_id = v_profile_id;

  if coalesce(v_member_status, '') <> 'approved' then
    raise exception 'Profile is not an approved hall member';
  end if;

  select exists (
    select 1
    from public.players p
    where p.id = p_player_id
      and (
        p.hall_id = p_hall_id
        or exists (
          select 1
          from public.team_players tp
          join public.tournaments t on t.id = tp.tournament_id
          where tp.player_id = p_player_id
            and t.hall_id = p_hall_id
        )
      )
  )
  into v_player_belongs_to_hall;

  if v_player_belongs_to_hall is distinct from true then
    raise exception 'Player does not belong to hall';
  end if;

  update public.players
     set hall_id = p_hall_id
   where id = p_player_id
     and hall_id is null;

  insert into public.player_profile_links (
    profile_id,
    hall_id,
    player_id
  )
  values (
    v_profile_id,
    p_hall_id,
    p_player_id
  )
  on conflict (profile_id, hall_id) do update
    set player_id = excluded.player_id,
        updated_at = now();
end;
$$;

grant execute on function public.link_my_profile_to_hall_player(uuid, uuid) to authenticated;

create or replace function public.tg_open_mvp_voting_on_tournament_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.completed, false)
     and (
       tg_op = 'INSERT'
       or coalesce(old.completed, false) = false
     ) then
    new.mvp_voting_ends_at := coalesce(
      new.mvp_voting_ends_at,
      now() + interval '12 hours'
    );
    new.mvp_votes_finalized := false;
    new.mvp_finalized_at := null;
    new.mvp_winner_player_id := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_open_mvp_voting_on_complete on public.tournaments;

create trigger trg_open_mvp_voting_on_complete
before insert or update of completed on public.tournaments
for each row
execute function public.tg_open_mvp_voting_on_tournament_complete();

commit;
