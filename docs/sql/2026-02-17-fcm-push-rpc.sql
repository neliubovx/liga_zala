-- FCM-friendly wrappers over existing push token RPCs.
-- Keeps backward compatibility with current profile_push_tokens schema.
-- Apply in Supabase SQL Editor.

begin;

create or replace function public.upsert_my_fcm_token(
  p_fcm_token text,
  p_device_id text default null,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.upsert_my_push_token(
    p_expo_push_token => p_fcm_token,
    p_device_id => p_device_id,
    p_platform => p_platform
  );
end;
$$;

create or replace function public.deactivate_my_fcm_token(
  p_fcm_token text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.deactivate_my_push_token(
    p_expo_push_token => p_fcm_token
  );
end;
$$;

grant execute on function public.upsert_my_fcm_token(text, text, text) to authenticated;
grant execute on function public.deactivate_my_fcm_token(text) to authenticated;

commit;
