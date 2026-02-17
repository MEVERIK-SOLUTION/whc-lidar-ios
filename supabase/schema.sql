-- Supabase schema for MEVERIK room scanner
-- Safe to run multiple times where possible.

-- Enable extensions (if not already)
create extension if not exists pgcrypto;

-- Table: scans
create table if not exists public.scans (
  id uuid primary key default gen_random_uuid(),
  scan_id text unique not null,
  room_name text,
  room_type text,
  length double precision,
  width double precision,
  height double precision,
  usdz_url text,
  floorplan_svg_url text,
  json_url text,
  scan_date timestamptz,
  device_model text,
  user_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes
create index if not exists scans_scan_id_idx on public.scans (scan_id);
create index if not exists scans_user_id_idx on public.scans (user_id);
create index if not exists scans_scan_date_idx on public.scans (scan_date);

-- updated_at trigger
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger scans_set_updated_at
before update on public.scans
for each row
execute function public.set_updated_at();

-- RLS for scans
alter table public.scans enable row level security;

drop policy if exists scans_select_all on public.scans;
create policy scans_select_all
on public.scans
for select
to public
using (true);

drop policy if exists scans_insert_all on public.scans;
create policy scans_insert_all
on public.scans
for insert
to public
with check (true);

-- Storage bucket: scans
insert into storage.buckets (id, name, public)
values ('scans', 'scans', true)
on conflict (id) do nothing;

-- Storage policies for scans bucket
-- Allow anyone to read files in bucket
drop policy if exists storage_scans_select_all on storage.objects;
create policy storage_scans_select_all
on storage.objects
for select
to public
using (bucket_id = 'scans');

-- Allow anyone to insert files in bucket
drop policy if exists storage_scans_insert_all on storage.objects;
create policy storage_scans_insert_all
on storage.objects
for insert
to public
with check (bucket_id = 'scans');
