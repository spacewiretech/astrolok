-- One round trip for what every signed-in call needs before it can do anything.
--
-- Every signed-in call to every function opened with the same PostgREST requests, one after
-- another: the session lookup, the `last_seen_at` stamp, `app_config` (on an instance with nothing
-- cached, which is 95% of them), and the caller's `users` row. On 2026-09-28 those were about 20
-- of the 44 requests a second the project was serving when it raised its high-CPU warning; the
-- queries themselves cost almost nothing, the requests did. This answers all of them at once.
--
-- `p_with_config` is off when the instance already holds config inside its minute, and
-- `p_with_user` when the function only needs to know who is calling. The stamp interval is passed
-- in, so the ten minutes stay written down once, in `_shared/db.ts`.
--
-- The row comes back as `to_jsonb(users) - 'chart'`. The function cuts it down to `USER_COLUMNS`
-- itself (`userColumnsOf` in `_shared/entitlement.ts`), and reads the table the old way if a column
-- it wants is missing, so a column added there and not here costs a request, not a wrong answer.
-- `chart` stays out because it is the one large column and no caller of this wants it.
--
-- It returns every `app_config` row, secrets included, which is why only service_role may call it.
-- Safe in either order against the functions deploy: until this exists, the functions fall back
-- to the separate requests.
create or replace function public.edge_caller(
  p_token_hash text,
  p_with_config boolean default true,
  p_with_user boolean default true,
  p_stamp_every_seconds integer default 600
)
returns jsonb
language plpgsql
volatile
set search_path = public
as $$
declare
  v_user_id uuid;
  v_expires_at timestamptz;
  v_last_seen_at timestamptz;
  v_user jsonb;
begin
  select s.user_id, s.expires_at, s.last_seen_at
    into v_user_id, v_expires_at, v_last_seen_at
    from public.user_sessions s
   where s.token_hash = p_token_hash;

  -- The same rule as the lookup it replaces: an expiry in the past is nobody.
  if v_expires_at is null or v_expires_at < now() then
    v_user_id := null;
  end if;

  if v_user_id is not null then
    -- Never stamped, or stamped longer ago than the interval. A clock ahead of ours is not stale.
    if v_last_seen_at is null
       or v_last_seen_at <= now() - make_interval(secs => greatest(p_stamp_every_seconds, 0)) then
      update public.user_sessions
         set last_seen_at = now()
       where token_hash = p_token_hash;
    end if;

    if p_with_user then
      select to_jsonb(u) - 'chart' into v_user from public.users u where u.user_id = v_user_id;
    end if;
  end if;

  return jsonb_build_object(
    'user_id', v_user_id,
    'user', v_user,
    'config', case when p_with_config then (
      select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'value', c.value)), '[]'::jsonb)
        from public.app_config c
    ) end
  );
end;
$$;

revoke all on function public.edge_caller(text, boolean, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.edge_caller(text, boolean, boolean, integer) to service_role;
