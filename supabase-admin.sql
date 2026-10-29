-- Lot Tag Desk: protect saved records (run AFTER supabase-setup.sql)
-- SQL Editor -> New query -> paste all of this -> Run. Safe to run again.
--
-- Anyone signed in can ADD records. Only the admin can EDIT or DELETE them:
--   * the admin account (email below), or
--   * anyone who enters the admin password.
-- The password is stored only as a bcrypt hash, in a schema the website cannot read.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.settings (key text primary key, value text not null);
insert into private.settings (key, value) values
  ('admin_email',   'shahiqiqbaltariq@gmail.com'),
  ('admin_pw_hash', '$2a$12$JKvLpewWpvPJV/3p6YP/puPD7W4BJtbzSIiguEfSuLU0LZDddFqAi')
on conflict (key) do update set value = excluded.value;

-- Who saved each record (shown on the Saved Records page)
alter table public.lots add column if not exists created_by_email text default (auth.jwt() ->> 'email');
alter table public.lots add column if not exists updated_by_email text;

-- Every edit keeps the previous version
create table if not exists public.lot_history (
  id          bigint generated always as identity primary key,
  sku         text not null,
  action      text not null check (action in ('edited','deleted')),
  old_data    jsonb not null,
  new_sku     text,
  changed_at  timestamptz not null default now(),
  changed_by  uuid default auth.uid(),
  changed_by_email text default (auth.jwt() ->> 'email')
);
alter table public.lot_history enable row level security;
drop policy if exists team_read on public.lot_history;
create policy team_read on public.lot_history for select to authenticated using (true);
revoke all on public.lot_history from anon;

-- Signed-in users may add and read lots, but not change or remove them directly
drop policy if exists team_update on public.lots;
drop policy if exists team_delete on public.lots;
drop trigger if exists lots_touch on public.lots;

-- Deletions go to history (replaces the earlier archive trigger)
create or replace function public.lots_after_delete() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('ltd.editing', true), '') = '1' then return old; end if;
  insert into public.deleted_lots (sku, data) values (old.sku, to_jsonb(old));
  insert into public.lot_history (sku, action, old_data) values (old.sku, 'deleted', to_jsonb(old));
  return old;
end $$;

-- ---------- admin checks ----------
create or replace function public.ltd_is_admin(p_password text) returns boolean
language plpgsql stable security definer set search_path = public, private, extensions as $$
declare v_email text; v_hash text;
begin
  if auth.uid() is null then return false; end if;
  select value into v_email from private.settings where key = 'admin_email';
  select value into v_hash  from private.settings where key = 'admin_pw_hash';
  if lower(coalesce(auth.jwt() ->> 'email', '')) = lower(v_email) then return true; end if;
  return p_password is not null and length(p_password) between 1 and 200
         and extensions.crypt(p_password, v_hash) = v_hash;
end $$;

-- Lets the page check a password before showing edit controls
create or replace function public.admin_check(p_password text) returns boolean
language sql stable security definer set search_path = public as $$ select public.ltd_is_admin(p_password) $$;

create or replace function public.admin_delete_lot(p_password text, p_sku text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.ltd_is_admin(p_password) then raise exception 'admin_required' using errcode = '42501'; end if;
  delete from public.lots where sku = p_sku;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;

-- Replace a saved record (the SKU may change when counts change). Keeps who/when it was first saved.
create or replace function public.admin_save_lot(p_password text, p_old_sku text, p_row jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare v_old public.lots; v_new public.lots;
begin
  if not public.ltd_is_admin(p_password) then raise exception 'admin_required' using errcode = '42501'; end if;
  select * into v_old from public.lots where sku = p_old_sku;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_new := jsonb_populate_record(null::public.lots, p_row);
  if v_new.sku <> p_old_sku and exists (select 1 from public.lots where sku = v_new.sku) then
    raise exception 'sku_exists' using errcode = '23505';
  end if;
  insert into public.lot_history (sku, action, old_data, new_sku) values (p_old_sku, 'edited', to_jsonb(v_old), v_new.sku);
  perform set_config('ltd.editing', '1', true);
  delete from public.lots where sku = p_old_sku;
  perform set_config('ltd.editing', '', true);
  v_new.created_at := v_old.created_at;  v_new.created_by := v_old.created_by;  v_new.created_by_email := v_old.created_by_email;
  v_new.updated_at := now();  v_new.updated_by := auth.uid();  v_new.updated_by_email := auth.jwt() ->> 'email';
  insert into public.lots select v_new.*;
end $$;

revoke all on function public.ltd_is_admin(text), public.admin_check(text), public.admin_delete_lot(text, text), public.admin_save_lot(text, text, jsonb) from public, anon;
grant execute on function public.admin_check(text), public.admin_delete_lot(text, text), public.admin_save_lot(text, text, jsonb) to authenticated;
