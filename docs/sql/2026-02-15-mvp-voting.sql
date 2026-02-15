-- MVP voting workflow (12h window after tournament completion)
-- Apply in Supabase SQL Editor.

begin;

create extension if not exists pgcrypto;

alter table public.tournaments
  add column if not exists mvp_voting_ends_at timestamptz,
  add column if not exists mvp_votes_finalized boolean not null default false,
  add column if not exists mvp_finalized_at timestamptz,
  add column if not exists mvp_winner_player_id uuid references public.players(id);

create table if not exists public.tournament_mvp_votes (
  id uuid primary key default gen_random_uuid(),
  hall_id uuid not null references public.halls(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  voter_profile_id uuid not null references public.profiles(id) on delete cascade,
  voter_player_id uuid not null references public.players(id) on delete cascade,
  candidate_player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index if not exists tournament_mvp_votes_unique_voter
  on public.tournament_mvp_votes (tournament_id, voter_profile_id);

create index if not exists tournament_mvp_votes_tournament_idx
  on public.tournament_mvp_votes (tournament_id);

create index if not exists tournament_mvp_votes_candidate_idx
  on public.tournament_mvp_votes (candidate_player_id);

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
  v_voter_player_ids uuid[];
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

  -- Maps auth profile -> participant player by display_name.
  -- Current app stores tournament participants in players.name,
  -- so we use this deterministic fallback mapping.
  select array_agg(distinct p.id)
    into v_voter_player_ids
  from public.profiles pr
  join public.players p
    on lower(trim(coalesce(p.name, ''))) = lower(trim(coalesce(pr.display_name, '')))
  join public.team_players tp
    on tp.player_id = p.id
   and tp.tournament_id = p_tournament_id
  where pr.id = v_profile_id;

  if coalesce(array_length(v_voter_player_ids, 1), 0) = 0 then
    raise exception 'Only tournament participants can vote';
  end if;

  if array_length(v_voter_player_ids, 1) > 1 then
    raise exception 'Ambiguous profile-to-player mapping. Set unique display_name.';
  end if;

  v_voter_player_id := v_voter_player_ids[1];

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

create or replace function public.finalize_tournament_mvp(
  p_tournament_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tournament record;
  v_winner_player_id uuid;
  v_votes_count int := 0;
begin
  select t.id,
         t.hall_id,
         t.completed,
         t.mvp_voting_ends_at,
         t.mvp_votes_finalized,
         t.mvp_winner_player_id
    into v_tournament
  from public.tournaments t
  where t.id = p_tournament_id
  for update;

  if not found then
    raise exception 'Tournament not found';
  end if;

  if v_tournament.completed is distinct from true then
    raise exception 'Tournament is not completed yet';
  end if;

  if coalesce(v_tournament.mvp_votes_finalized, false) then
    return jsonb_build_object(
      'status', 'already_finalized',
      'winner_player_id', v_tournament.mvp_winner_player_id
    );
  end if;

  if v_tournament.mvp_voting_ends_at is null then
    return jsonb_build_object('status', 'voting_not_opened');
  end if;

  if now() < v_tournament.mvp_voting_ends_at then
    return jsonb_build_object(
      'status', 'voting_open',
      'ends_at', v_tournament.mvp_voting_ends_at
    );
  end if;

  select v.candidate_player_id, count(*)::int
    into v_winner_player_id, v_votes_count
  from public.tournament_mvp_votes v
  where v.tournament_id = p_tournament_id
  group by v.candidate_player_id
  order by count(*) desc, v.candidate_player_id
  limit 1;

  if v_winner_player_id is not null then
    update public.player_stats ps
       set mvp_count = coalesce(ps.mvp_count, 0) + 1
     where ps.hall_id = v_tournament.hall_id
       and ps.user_id = v_winner_player_id;
  end if;

  update public.tournaments t
     set mvp_votes_finalized = true,
         mvp_finalized_at = now(),
         mvp_winner_player_id = v_winner_player_id
   where t.id = p_tournament_id;

  return jsonb_build_object(
    'status', 'finalized',
    'winner_player_id', v_winner_player_id,
    'votes', v_votes_count
  );
end;
$$;

create or replace function public.finalize_due_mvp_votes(
  p_hall_id uuid
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_count int := 0;
begin
  for v_row in
    select t.id
    from public.tournaments t
    where t.hall_id = p_hall_id
      and t.completed = true
      and t.mvp_voting_ends_at is not null
      and t.mvp_voting_ends_at <= now()
      and coalesce(t.mvp_votes_finalized, false) = false
  loop
    perform public.finalize_tournament_mvp(v_row.id);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.cast_tournament_mvp_vote(uuid, uuid) to authenticated;
grant execute on function public.finalize_tournament_mvp(uuid) to authenticated;
grant execute on function public.finalize_due_mvp_votes(uuid) to authenticated;

commit;
