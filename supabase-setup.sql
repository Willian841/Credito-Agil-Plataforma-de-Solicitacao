-- Crédito Ágil: estrutura inicial de solicitações e acesso administrativo.
-- Revise a política de privacidade/consentimento antes de produção.
create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.loan_applications (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  full_name text not null check (char_length(full_name) between 3 and 160),
  phone text not null check (char_length(phone) between 8 and 30),
  email text not null check (char_length(email) between 5 and 254),
  cpf text not null check (cpf ~ '^[0-9]{11}$'),
  loan_amount numeric(12,2) not null check (loan_amount between 500 and 10000),
  loan_term integer not null check (loan_term in (6,12,18,24,36)),
  monthly_payment numeric(12,2) not null check (monthly_payment > 0),
  total_payment numeric(12,2) not null check (total_payment > 0),
  income numeric(12,2) check (income is null or income >= 0),
  purpose text,
  consent_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
alter table public.loan_applications enable row level security;

drop policy if exists "Admins can read their own admin membership" on public.admin_users;
create policy "Admins can read their own admin membership"
on public.admin_users for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Public can submit applications" on public.loan_applications;
create policy "Public can submit applications"
on public.loan_applications for insert to anon, authenticated
with check (
  char_length(full_name) between 3 and 160
  and char_length(phone) between 8 and 30
  and char_length(email) between 5 and 254
  and cpf ~ '^[0-9]{11}$'
  and loan_amount between 500 and 10000
  and loan_term in (6,12,18,24,36)
);

drop policy if exists "Only listed admins can read applications" on public.loan_applications;
create policy "Only listed admins can read applications"
on public.loan_applications for select to authenticated
using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));

revoke all on public.loan_applications from anon, authenticated;
grant insert on public.loan_applications to anon, authenticated;
grant select on public.loan_applications to authenticated;
revoke all on public.admin_users from anon, authenticated;
grant select on public.admin_users to authenticated;

-- SETUP MANUAL (executar depois de criar o usuário em Supabase > Authentication > Users):
-- insert into public.admin_users (user_id) values ('UUID_DO_SEU_USUARIO_AUTH');
-- Não habilite acesso público de leitura. Nunca exponha a chave service_role no frontend.
