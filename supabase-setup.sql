-- Lot Tag Desk: database setup for Supabase
-- Run once in your Supabase project: SQL Editor -> New query -> paste all of this -> Run.
-- Safe to run again; it only creates what is missing.

-- ---------- Code tables ----------
create table if not exists public.parties (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('supplier','customer')),
  name        text not null check (char_length(name) between 1 and 200),
  code        text not null unique check (code ~ '^[A-Z]{1,4}$'),  -- unique across suppliers AND customers
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid()
);

create table if not exists public.brands (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 200),
  code        text not null unique check (code ~ '^[A-Z]{1,4}$'),
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid()
);

create table if not exists public.product_types (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 200),
  code        text not null unique check (code ~ '^[A-Z]{1,4}$'),
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid()
);

-- ---------- Lots and tags ----------
create table if not exists public.lots (
  sku           text primary key check (char_length(sku) between 3 and 80),
  mode          text not null check (mode in ('supplier','preqc','postqc')),
  prefix        text,
  party         text not null,
  party_code    text not null,
  brand         text,
  brand_code    text,
  product       text,
  product_code  text,
  lot_date      date not null,
  grade         text check (grade is null or grade in ('A','B','C','A/B','A/B/C','B/C')),
  ready         integer not null default 0 check (ready   >= 0),
  washing       integer not null default 0 check (washing >= 0),
  mending       integer not null default 0 check (mending >= 0),
  unrec         integer not null default 0 check (unrec   >= 0),
  qty           integer check (qty is null or qty >= 0),
  total         integer not null check (total >= 0),
  tags          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  created_by    uuid default auth.uid(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid default auth.uid()
);
create index if not exists lots_created_at_idx on public.lots (created_at desc);

-- ---------- History ----------
create table if not exists public.print_log (
  id          bigint generated always as identity primary key,
  lot_sku     text,
  codes       text[] not null,
  sticker_count integer not null,
  label_w_mm  integer not null,
  label_h_mm  integer not null,
  printed_at  timestamptz not null default now(),
  printed_by  uuid default auth.uid()
);

create table if not exists public.scan_log (
  id          bigint generated always as identity primary key,
  code        text not null,
  matched_sku text,
  scanned_at  timestamptz not null default now(),
  scanned_by  uuid default auth.uid()
);

create table if not exists public.deleted_lots (
  sku         text not null,
  data        jsonb not null,
  deleted_at  timestamptz not null default now(),
  deleted_by  uuid default auth.uid()
);

-- Keep a copy of every deleted lot and stamp who changed a lot last.
create or replace function public.lots_before_update() returns trigger language plpgsql as $$
begin new.updated_at := now(); new.updated_by := auth.uid(); return new; end $$;
drop trigger if exists lots_touch on public.lots;
create trigger lots_touch before update on public.lots for each row execute function public.lots_before_update();

create or replace function public.lots_after_delete() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.deleted_lots (sku, data) values (old.sku, to_jsonb(old)); return old; end $$;
drop trigger if exists lots_archive on public.lots;
create trigger lots_archive after delete on public.lots for each row execute function public.lots_after_delete();

-- ---------- Access: signed-in team members only ----------
alter table public.parties       enable row level security;
alter table public.brands        enable row level security;
alter table public.product_types enable row level security;
alter table public.lots          enable row level security;
alter table public.print_log     enable row level security;
alter table public.scan_log      enable row level security;
alter table public.deleted_lots  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['parties','brands','product_types','lots'] loop
    execute format('drop policy if exists team_read on public.%I', t);
    execute format('drop policy if exists team_insert on public.%I', t);
    execute format('drop policy if exists team_update on public.%I', t);
    execute format('drop policy if exists team_delete on public.%I', t);
    execute format('create policy team_read   on public.%I for select to authenticated using (true)', t);
    execute format('create policy team_insert on public.%I for insert to authenticated with check (true)', t);
    execute format('create policy team_update on public.%I for update to authenticated using (true) with check (true)', t);
    execute format('create policy team_delete on public.%I for delete to authenticated using (true)', t);
  end loop;
  -- history: anyone signed in can add and read, nobody can edit or remove
  foreach t in array array['print_log','scan_log'] loop
    execute format('drop policy if exists team_read on public.%I', t);
    execute format('drop policy if exists team_insert on public.%I', t);
    execute format('create policy team_read   on public.%I for select to authenticated using (true)', t);
    execute format('create policy team_insert on public.%I for insert to authenticated with check (true)', t);
  end loop;
  execute 'drop policy if exists team_read on public.deleted_lots';
  execute 'create policy team_read on public.deleted_lots for select to authenticated using (true)';
end $$;

-- Nothing is readable or writable without signing in.
revoke all on public.parties, public.brands, public.product_types, public.lots,
              public.print_log, public.scan_log, public.deleted_lots from anon;

-- ---------- Live updates between devices ----------
do $$
declare t text;
begin
  foreach t in array array['lots','parties','brands','product_types'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- Starting codes (skipped if they already exist) ----------
insert into public.parties (kind, name, code) values ('supplier','Abdul Kareem','AK') on conflict (code) do nothing;
insert into public.brands (name, code) values ('Patagonia','P') on conflict (code) do nothing;
insert into public.product_types (name, code) values ('Fleece Jackets','FJ') on conflict (code) do nothing;
