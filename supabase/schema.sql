-- Painel Financeiro — Supabase schema.
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- One row per user. Everything in it except the version and timestamp is
-- encrypted on the user's device (see flutter_app/lib/src/crypto.dart), so an
-- admin browsing this table sees only opaque base64.

create table if not exists public.vaults (
  user_id              uuid primary key references auth.users (id) on delete cascade,
  kdf                  jsonb not null,             -- {"alg": "pbkdf2-sha256", "iterations": 600000}; not secret
  wrapped_key_password text  not null,             -- data key, encrypted with a key derived from the password
  wrapped_key_recovery text  not null,             -- data key, encrypted with the recovery key
  ciphertext           text  not null check (length(ciphertext) < 5000000),
  version              integer not null default 1, -- optimistic concurrency between devices
  updated_at           timestamptz not null default now()
);

-- Row-level security: each signed-in user can reach only their own row.
alter table public.vaults enable row level security;

drop policy if exists "vaults: read own"   on public.vaults;
drop policy if exists "vaults: insert own" on public.vaults;
drop policy if exists "vaults: update own" on public.vaults;
drop policy if exists "vaults: delete own" on public.vaults;

create policy "vaults: read own"   on public.vaults for select to authenticated using ((select auth.uid()) = user_id);
create policy "vaults: insert own" on public.vaults for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "vaults: update own" on public.vaults for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "vaults: delete own" on public.vaults for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.vaults from anon;

-- "Apagar conta": a signed-in user deletes their own auth user; the vault row
-- goes with it (on delete cascade). Required for GDPR erasure.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
