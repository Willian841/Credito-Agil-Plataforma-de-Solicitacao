-- Crédito Ágil: consentimento e integração de notificações automáticas por WhatsApp.
-- Execute UMA VEZ em Supabase > SQL Editor > New query.
-- O token da Meta nunca deve ficar no HTML público.

alter table public.loan_applications
  add column if not exists whatsapp_opt_in boolean not null default false;
alter table public.loan_applications
  add column if not exists whatsapp_opt_in_at timestamptz;

drop function if exists public.submit_loan_application(text,text,text,text,numeric,integer,numeric,numeric,numeric,text);

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
  p_purpose text default null,
  p_whatsapp_opt_in boolean default false
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
    monthly_payment, total_payment, income, purpose, consent_at,
    tracking_code_hash, whatsapp_opt_in, whatsapp_opt_in_at
  ) values (
    trim(p_full_name), trim(p_phone), trim(p_email), p_cpf,
    p_loan_amount, p_loan_term, p_monthly_payment, p_total_payment,
    p_income, nullif(trim(coalesce(p_purpose,'')),''), now(),
    encode(digest(v_code, 'sha256'), 'hex'),
    coalesce(p_whatsapp_opt_in, false),
    case when coalesce(p_whatsapp_opt_in, false) then now() else null end
  ) returning id into v_application_id;

  return jsonb_build_object('application_id', v_application_id, 'tracking_code', v_code);
end;
$$;

revoke all on function public.submit_loan_application(text,text,text,text,numeric,integer,numeric,numeric,numeric,text,boolean) from public;
grant execute on function public.submit_loan_application(text,text,text,text,numeric,integer,numeric,numeric,numeric,text,boolean) to anon, authenticated;
