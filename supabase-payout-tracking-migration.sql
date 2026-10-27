-- Crédito Ágil: acompanhamento por código único e dados de recebimento após aprovação.
-- Execute UMA VEZ no Supabase > SQL Editor > New query, depois de supabase-status-migration.sql.
-- Não coleta nem armazena dados de cartão. A chave Pix ou os dados bancários ficam visíveis apenas a administradores autorizados.

create extension if not exists pgcrypto;

alter table public.loan_applications
  add column if not exists tracking_code_hash text unique;

create table if not exists public.payout_details (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.loan_applications(id) on delete cascade,
  payment_method text not null check (payment_method in ('pix','bank')),
  pix_type text,
  pix_key text,
  bank_name text,
  bank_code text,
  agency text,
  account_number text,
  account_type text,
  account_holder text,
  updated_at timestamptz not null default now(),
  constraint payout_details_method_fields_check check (
    (payment_method = 'pix'
      and pix_type in ('CPF','CNPJ','E-mail','Telefone','Chave aleatória')
      and char_length(trim(pix_key)) between 3 and 160
      and bank_name is null and agency is null and account_number is null and account_holder is null)
    or
    (payment_method = 'bank'
      and char_length(trim(bank_name)) between 2 and 120
      and char_length(trim(agency)) between 1 and 30
      and char_length(trim(account_number)) between 1 and 40
      and account_type in ('Corrente','Poupança','Pagamento')
      and char_length(trim(account_holder)) between 3 and 160
      and pix_type is null and pix_key is null)
  )
);

alter table public.payout_details enable row level security;
revoke all on public.payout_details from anon, authenticated;
grant select on public.payout_details to authenticated;

drop policy if exists "Only admins can view payout details" on public.payout_details;
create policy "Only admins can view payout details"
on public.payout_details for select to authenticated
using (exists (
  select 1 from public.admin_users a where a.user_id = (select auth.uid())
));

create or replace function public.submit_loan_application(
  p_full_name text,
  p_phone text,
  p_email text,
  p_cpf text,
  p_loan_amount numeric,
  p_loan_term integer,
  p_monthly_payment numeric,
  p_total_payment numeric,
  p_income numeric default null,
  p_purpose text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_code text;
  v_application_id uuid;
begin
  if char_length(trim(coalesce(p_full_name,''))) not between 3 and 160
     or char_length(trim(coalesce(p_phone,''))) not between 8 and 30
     or char_length(trim(coalesce(p_email,''))) not between 5 and 254
     or coalesce(p_cpf,'') !~ '^[0-9]{11}$'
     or p_loan_amount not between 500 and 10000
     or p_loan_term not in (6,12,18,24,36)
     or p_monthly_payment <= 0
     or p_total_payment <= 0
     or (p_income is not null and p_income < 0) then
    raise exception 'Dados da solicitação inválidos';
  end if;

  v_code := upper(encode(gen_random_bytes(16), 'hex'));
  insert into public.loan_applications (
    full_name, phone, email, cpf, loan_amount, loan_term,
    monthly_payment, total_payment, income, purpose, consent_at, tracking_code_hash
  ) values (
    trim(p_full_name), trim(p_phone), trim(p_email), p_cpf,
    p_loan_amount, p_loan_term, p_monthly_payment, p_total_payment,
    p_income, nullif(trim(coalesce(p_purpose,'')),''), now(),
    encode(digest(v_code, 'sha256'), 'hex')
  ) returning id into v_application_id;

  return jsonb_build_object('application_id', v_application_id, 'tracking_code', v_code);
end;
$$;

create or replace function public.get_application_status(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_result jsonb;
begin
  if coalesce(p_code,'') !~ '^[A-Fa-f0-9]{32}$' then return null; end if;
  select jsonb_build_object(
    'status', la.status,
    'loan_amount', la.loan_amount,
    'created_at', la.created_at,
    'has_payout_details', exists(select 1 from public.payout_details pd where pd.application_id = la.id)
  )
  into v_result
  from public.loan_applications la
  where la.tracking_code_hash = encode(digest(upper(p_code), 'sha256'), 'hex')
  limit 1;
  return v_result;
end;
$$;

create or replace function public.save_payout_details(
  p_code text,
  p_payment_method text,
  p_pix_type text default null,
  p_pix_key text default null,
  p_bank_name text default null,
  p_bank_code text default null,
  p_agency text default null,
  p_account_number text default null,
  p_account_type text default null,
  p_account_holder text default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_application_id uuid;
begin
  if coalesce(p_code,'') !~ '^[A-Fa-f0-9]{32}$' then return false; end if;
  select id into v_application_id
  from public.loan_applications
  where tracking_code_hash = encode(digest(upper(p_code), 'sha256'), 'hex')
    and status = 'Aprovado'
  limit 1;
  if v_application_id is null then return false; end if;

  if p_payment_method = 'pix' then
    if p_pix_type not in ('CPF','CNPJ','E-mail','Telefone','Chave aleatória')
       or char_length(trim(coalesce(p_pix_key,''))) not between 3 and 160 then
      raise exception 'Informe um tipo e uma chave Pix válidos';
    end if;
    insert into public.payout_details (
      application_id,payment_method,pix_type,pix_key,bank_name,bank_code,agency,account_number,account_type,account_holder,updated_at
    ) values (
      v_application_id,'pix',p_pix_type,trim(p_pix_key),null,null,null,null,null,null,now()
    )
    on conflict (application_id) do update set
      payment_method='pix', pix_type=excluded.pix_type, pix_key=excluded.pix_key,
      bank_name=null, bank_code=null, agency=null, account_number=null, account_type=null, account_holder=null, updated_at=now();
  elsif p_payment_method = 'bank' then
    if char_length(trim(coalesce(p_bank_name,''))) not between 2 and 120
       or char_length(trim(coalesce(p_agency,''))) not between 1 and 30
       or char_length(trim(coalesce(p_account_number,''))) not between 1 and 40
       or p_account_type not in ('Corrente','Poupança','Pagamento')
       or char_length(trim(coalesce(p_account_holder,''))) not between 3 and 160 then
      raise exception 'Informe os dados bancários obrigatórios';
    end if;
    insert into public.payout_details (
      application_id,payment_method,pix_type,pix_key,bank_name,bank_code,agency,account_number,account_type,account_holder,updated_at
    ) values (
      v_application_id,'bank',null,null,trim(p_bank_name),nullif(trim(coalesce(p_bank_code,'')),''),trim(p_agency),trim(p_account_number),p_account_type,trim(p_account_holder),now()
    )
    on conflict (application_id) do update set
      payment_method='bank', pix_type=null, pix_key=null,
      bank_name=excluded.bank_name, bank_code=excluded.bank_code, agency=excluded.agency,
      account_number=excluded.account_number, account_type=excluded.account_type, account_holder=excluded.account_holder, updated_at=now();
  else
    raise exception 'Forma de recebimento inválida';
  end if;
  return true;
end;
$$;

revoke all on function public.submit_loan_application(text,text,text,text,numeric,integer,numeric,numeric,numeric,text) from public;
revoke all on function public.get_application_status(text) from public;
revoke all on function public.save_payout_details(text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.submit_loan_application(text,text,text,text,numeric,integer,numeric,numeric,numeric,text) to anon, authenticated;
grant execute on function public.get_application_status(text) to anon, authenticated;
grant execute on function public.save_payout_details(text,text,text,text,text,text,text,text,text,text) to anon, authenticated;

-- O código possui 128 bits aleatórios; somente seu hash fica salvo no banco.
-- A função pública retorna apenas status/valor/data e nunca revela CPF, contato ou dados de recebimento.
