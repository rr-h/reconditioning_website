-- Reconditioning programme tracker: Supabase setup
-- Run this once in Supabase SQL Editor.
-- This creates a locked table plus RPC functions used by the static website.
-- Do not put the service role key in the website.
--
-- Fix included: Supabase commonly installs extensions in the "extensions" schema.
-- The RPC functions therefore call extensions.digest(...) explicitly.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.reconditioning_tracker_profiles (
  sync_id text primary key,
  secret_hash text not null,
  data jsonb not null default '{}'::jsonb,
  last_device text,
  client_updated_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.reconditioning_tracker_profiles enable row level security;
-- RLS is enabled, but not forced, so the SECURITY DEFINER RPC functions can operate.
-- Direct anon/authenticated table access is revoked below.

revoke all on table public.reconditioning_tracker_profiles from anon;
revoke all on table public.reconditioning_tracker_profiles from authenticated;
revoke all on table public.reconditioning_tracker_profiles from public;

create or replace function public.reconditioning_hash_secret(
  p_sync_id text,
  p_secret text
)
returns text
language sql
stable
set search_path = public, extensions, pg_temp
as $$
  select encode(
    extensions.digest((coalesce(p_secret, '') || ':' || coalesce(p_sync_id, ''))::text, 'sha256'::text),
    'hex'
  )
$$;

revoke all on function public.reconditioning_hash_secret(text, text) from public;

create or replace function public.reconditioning_pull(
  p_sync_id text,
  p_secret text
)
returns table (
  profile_exists boolean,
  data jsonb,
  client_updated_at timestamptz,
  server_updated_at timestamptz,
  last_device text
)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
  v_has_id boolean;
begin
  if p_sync_id is null or length(p_sync_id) < 32 or p_secret is null or length(p_secret) < 32 then
    raise exception 'Invalid sync credentials';
  end if;

  select exists (
    select 1 from public.reconditioning_tracker_profiles t where t.sync_id = p_sync_id
  ) into v_has_id;

  if not v_has_id then
    return query select false, '{}'::jsonb, null::timestamptz, null::timestamptz, null::text;
    return;
  end if;

  v_hash := public.reconditioning_hash_secret(p_sync_id, p_secret);

  return query
  select true, t.data, t.client_updated_at, t.updated_at, t.last_device
  from public.reconditioning_tracker_profiles t
  where t.sync_id = p_sync_id
    and t.secret_hash = v_hash;

  if not found then
    raise exception 'Invalid sync phrase for this profile';
  end if;
end;
$$;

create or replace function public.reconditioning_push(
  p_sync_id text,
  p_secret text,
  p_data jsonb,
  p_client_updated_at timestamptz,
  p_device_name text default null
)
returns table (
  data jsonb,
  client_updated_at timestamptz,
  server_updated_at timestamptz,
  last_device text
)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
  v_existing public.reconditioning_tracker_profiles%rowtype;
begin
  if p_sync_id is null or length(p_sync_id) < 32 or p_secret is null or length(p_secret) < 32 then
    raise exception 'Invalid sync credentials';
  end if;

  v_hash := public.reconditioning_hash_secret(p_sync_id, p_secret);

  select * into v_existing
  from public.reconditioning_tracker_profiles t
  where t.sync_id = p_sync_id;

  if not found then
    insert into public.reconditioning_tracker_profiles (
      sync_id,
      secret_hash,
      data,
      client_updated_at,
      last_device,
      updated_at
    ) values (
      p_sync_id,
      v_hash,
      coalesce(p_data, '{}'::jsonb),
      coalesce(p_client_updated_at, timezone('utc', now())),
      left(coalesce(p_device_name, 'unknown device'), 120),
      timezone('utc', now())
    );
  else
    if v_existing.secret_hash <> v_hash then
      raise exception 'Invalid sync phrase for this profile';
    end if;

    update public.reconditioning_tracker_profiles
    set data = coalesce(p_data, '{}'::jsonb),
        client_updated_at = coalesce(p_client_updated_at, timezone('utc', now())),
        last_device = left(coalesce(p_device_name, 'unknown device'), 120),
        updated_at = timezone('utc', now())
    where sync_id = p_sync_id
      and secret_hash = v_hash;
  end if;

  return query
  select t.data, t.client_updated_at, t.updated_at, t.last_device
  from public.reconditioning_tracker_profiles t
  where t.sync_id = p_sync_id
    and t.secret_hash = v_hash;
end;
$$;

revoke all on function public.reconditioning_pull(text, text) from public;
revoke all on function public.reconditioning_push(text, text, jsonb, timestamptz, text) from public;
grant execute on function public.reconditioning_pull(text, text) to anon, authenticated;
grant execute on function public.reconditioning_push(text, text, jsonb, timestamptz, text) to anon, authenticated;

-- Smoke test: this should return a 64-character SHA-256 hex string.
select public.reconditioning_hash_secret('01234567890123456789012345678901', '01234567890123456789012345678901') as setup_test_hash;
