-- MVP voting: explicit profile <-> player link
-- Apply AFTER 2026-02-15-mvp-voting.sql

begin;

create table if not exists public.player_profile_links (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  hall_id uuid not null references public.halls(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (profile_id, hall_id),
  unique (hall_id, player_id)
);

create index if not exists player_profile_links_profile_idx
  on public.player_profile_links (profile_id);

create index if not exists player_profile_links_hall_idx
  on public.player_profile_links (hall_id);

create or replace function public.link_my_profile_to_tournament_player(
  p_tournament_id uuid,
  p_player_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
  v_hall_id uuid;
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  select t.hall_id
    into v_hall_id
  from public.tournaments t
  where t.id = p_tournament_id;

  if not found then
    raise exception 'Tournament not found';
  end if;

  if not exists (
    select 1
    from public.team_players tp
    where tp.tournament_id = p_tournament_id
      and tp.player_id = p_player_id
  ) then
    raise exception 'Player is not a participant of this tournament';
  end if;

  insert into public.player_profile_links (
    profile_id,
    hall_id,
    player_id
  )
  values (
    v_profile_id,
    v_hall_id,
    p_player_id
  )
  on conflict (profile_id, hall_id) do update
    set player_id = excluded.player_id,
        updated_at = now();
end;
$$;

create or replace function public.cast_tournament_mvp_vote(
  p_tournament_id uuid,
  p_candidate_player_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid := auth.uid();
  v_hall_id uuid;
  v_completed boolean;
  v_voting_ends_at timestamptz;
  v_voter_player_id uuid;
begin
  if v_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  select t.hall_id, t.completed, t.mvp_voting_ends_at
    into v_hall_id, v_completed, v_voting_ends_at
  from public.tournaments t
  where t.id = p_tournament_id;

  if not found then
    raise exception 'Tournament not found';
  end if;

  if v_completed is distinct from true then
    raise exception 'Tournament is not completed yet';
  end if;

  if v_voting_ends_at is null then
    raise exception 'MVP voting is not opened';
  end if;

  if now() > v_voting_ends_at then
    raise exception 'Voting closed';
  end if;

  if not exists (
    select 1
    from public.team_players tp
    where tp.tournament_id = p_tournament_id
      and tp.player_id = p_candidate_player_id
  ) then
    raise exception 'Candidate is not a participant of this tournament';
  end if;

  select ppl.player_id
    into v_voter_player_id
  from public.player_profile_links ppl
  where ppl.profile_id = v_profile_id
    and ppl.hall_id = v_hall_id;

  if v_voter_player_id is null then
    raise exception 'Profile is not linked to a tournament participant';
  end if;

  if not exists (
    select 1
    from public.team_players tp
    where tp.tournament_id = p_tournament_id
      and tp.player_id = v_voter_player_id
  ) then
    raise exception 'Only tournament participants can vote';
  end if;

  insert into public.tournament_mvp_votes (
    hall_id,
    tournament_id,
    voter_profile_id,
    voter_player_id,
    candidate_player_id
  )
  values (
    v_hall_id,
    p_tournament_id,
    v_profile_id,
    v_voter_player_id,
    p_candidate_player_id
  )
  on conflict (tournament_id, voter_profile_id) do update
    set candidate_player_id = excluded.candidate_player_id,
        voter_player_id = excluded.voter_player_id,
        created_at = now();
end;
$$;

grant execute on function public.link_my_profile_to_tournament_player(uuid, uuid) to authenticated;

commit;
