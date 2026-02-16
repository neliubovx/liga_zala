-- Hotfix for ON CONFLICT error in notification_queue
-- Error: there is no unique or exclusion constraint matching the ON CONFLICT specification

begin;

-- Remove potential duplicates before creating a full unique index.
with ranked as (
  select
    id,
    row_number() over (
      partition by profile_id, tournament_id, kind, channel
      order by created_at desc, id desc
    ) as rn
  from public.notification_queue
)
delete from public.notification_queue q
using ranked r
where q.id = r.id
  and r.rn > 1;

drop index if exists public.notification_queue_unique_profile_tournament_kind_channel;

create unique index if not exists notification_queue_unique_profile_tournament_kind_channel
  on public.notification_queue (profile_id, tournament_id, kind, channel);

commit;
