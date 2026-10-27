-- Crédito Ágil: habilita status administrativo nas solicitações existentes.
-- Execute este arquivo UMA VEZ no Supabase > SQL Editor > New query.
alter table public.loan_applications
  add column if not exists status text not null default 'Pendente';

alter table public.loan_applications
  drop constraint if exists loan_applications_status_check;

alter table public.loan_applications
  add constraint loan_applications_status_check
  check (status in ('Pendente', 'Aprovado', 'Recusado'));

drop policy if exists "Only listed admins can update application status" on public.loan_applications;
create policy "Only listed admins can update application status"
on public.loan_applications
for update to authenticated
using (
  exists (
    select 1 from public.admin_users a
    where a.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.admin_users a
    where a.user_id = (select auth.uid())
  )
);

grant update (status) on public.loan_applications to authenticated;
