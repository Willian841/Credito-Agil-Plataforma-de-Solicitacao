-- Crédito Ágil: recursos administrativos adicionais
-- Execute no SQL Editor do Supabase antes de usar histórico/notas/arquivamento compartilhado.
create schema if not exists private;

create or replace function private.credito_agil_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users au
    where coalesce(
      to_jsonb(au)->>'user_id',
      to_jsonb(au)->>'id',
      to_jsonb(au)->>'admin_id'
    ) = (select auth.uid())::text
  );
$$;

revoke all on function private.credito_agil_is_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.credito_agil_is_admin() to authenticated;

create table if not exists public.admin_application_notes (
  id uuid primary key default gen_random_uuid(),
  application_id text not null,
  note text not null check (char_length(note) between 1 and 3000),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_application_events (
  id uuid primary key default gen_random_uuid(),
  application_id text not null,
  event_type text not null check (event_type in ('status_changed','note_added','archived','restored')),
  old_value text,
  new_value text,
  details text,
  actor_id uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_application_archive (
  application_id text primary key,
  archived_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  archived_at timestamptz not null default now()
);

alter table public.admin_application_notes enable row level security;
alter table public.admin_application_events enable row level security;
alter table public.admin_application_archive enable row level security;

revoke all on public.admin_application_notes, public.admin_application_events, public.admin_application_archive from public, anon, authenticated;
grant select, insert on public.admin_application_notes to authenticated;
grant select, insert on public.admin_application_events to authenticated;
grant select, insert, delete on public.admin_application_archive to authenticated;

drop policy if exists "admins manage application notes" on public.admin_application_notes;
create policy "admins manage application notes"
on public.admin_application_notes for all to authenticated
using ((select private.credito_agil_is_admin()))
with check ((select private.credito_agil_is_admin()));

drop policy if exists "admins manage application events" on public.admin_application_events;
create policy "admins manage application events"
on public.admin_application_events for all to authenticated
using ((select private.credito_agil_is_admin()))
with check ((select private.credito_agil_is_admin()));

drop policy if exists "admins manage application archive" on public.admin_application_archive;
create policy "admins manage application archive"
on public.admin_application_archive for all to authenticated
using ((select private.credito_agil_is_admin()))
with check ((select private.credito_agil_is_admin()));

create index if not exists admin_application_notes_app_created_idx
on public.admin_application_notes (application_id, created_at desc);
create index if not exists admin_application_events_app_created_idx
on public.admin_application_events (application_id, created_at desc);
