-- CAN42 | 001_initial_schema.sql
-- Run ONCE in Supabase Dashboard > SQL Editor. Run 001, 002, 003, 004 in order.

-- 1. PROFILES (one row per auth user; created automatically by trigger in 003)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 100),
  email text not null,
  referral_code text not null unique,
  referred_by uuid references public.profiles(id) on delete set null,
  status text not null default 'active' check (status in ('active','suspended','banned')),
  terms_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint no_self_referral check (referred_by is null or referred_by <> id)
);

-- 2. USER ROLES (normal users have NO row here; only admins do)
create table public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','super_admin')),
  granted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

-- 3. WALLETS (authoritative balances; changed ONLY by SECURITY DEFINER functions)
create table public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  available_points bigint not null default 0 check (available_points >= 0),
  pending_points   bigint not null default 0 check (pending_points   >= 0),
  reserved_points  bigint not null default 0 check (reserved_points  >= 0),
  lifetime_earned  bigint not null default 0 check (lifetime_earned  >= 0),
  total_withdrawn  bigint not null default 0 check (total_withdrawn  >= 0),
  updated_at timestamptz not null default now()
);

-- 4. REWARD LEDGER (append-only audit trail; see ledger_guard trigger below)
-- points is signed. Credits are positive. Reserve/reversal rows are negative.
-- withdrawal_paid rows are informational (the money left reserved_points, not available_points).
create table public.reward_ledger (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('TX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
  user_id uuid not null references public.profiles(id) on delete restrict,
  entry_type text not null check (entry_type in
    ('video_reward','ad_reward','referral_reward','withdrawal_reserve','withdrawal_release','withdrawal_paid','reversal','admin_adjustment')),
  status text not null default 'pending' check (status in ('pending','approved','rejected','completed','reversed')),
  points bigint not null check (points <> 0),
  source_type text,
  source_id uuid,
  idempotency_key text,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index reward_ledger_idem on public.reward_ledger(user_id, idempotency_key) where idempotency_key is not null;
create index reward_ledger_user_created on public.reward_ledger(user_id, created_at desc);

create or replace function public.ledger_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Ledger rows cannot be deleted'; end if;
  if new.id <> old.id or new.reference <> old.reference or new.user_id <> old.user_id
     or new.entry_type <> old.entry_type or new.points <> old.points
     or new.idempotency_key is distinct from old.idempotency_key then
    raise exception 'Ledger rows are immutable except status and note';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger reward_ledger_guard before update or delete on public.reward_ledger
  for each row execute function public.ledger_guard();

-- 5. CAMPAIGNS
create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('video','advertisement')),
  title text not null check (char_length(title) between 3 and 150),
  description text,
  reward_points integer not null check (reward_points > 0),
  budget_points bigint not null check (budget_points >= 0),
  spent_points bigint not null default 0 check (spent_points >= 0),
  max_completions integer check (max_completions is null or max_completions > 0),
  completions_count integer not null default 0 check (completions_count >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft','active','paused','stopped','completed')),
  eligibility jsonb not null default '{}'::jsonb,
  verification_method text not null default 'manual_review' check (verification_method in ('manual_review','provider_callback')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint campaign_dates check (ends_at is null or starts_at is null or ends_at > starts_at),
  constraint campaign_budget check (spent_points <= budget_points)
);
create index campaigns_status_type on public.campaigns(status, type);

-- 6. VIDEOS (only original or advertiser-authorized content)
create table public.videos (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  video_url text not null,
  thumbnail_url text,
  duration_seconds integer check (duration_seconds is null or duration_seconds > 0),
  source text not null check (source in ('original','advertiser_authorized')),
  rights_confirmed boolean not null default false,
  created_at timestamptz not null default now()
);
create index videos_campaign on public.videos(campaign_id);

-- 7. ADVERTISEMENTS
create table public.advertisements (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  ad_url text,
  image_url text,
  provider_name text,
  provider_permits_rewards boolean not null default false,
  requirements text,
  created_at timestamptz not null default now()
);
create index advertisements_campaign on public.advertisements(campaign_id);

-- 8. TASKS
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  title text not null,
  instructions text,
  reward_points integer not null check (reward_points > 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index tasks_campaign on public.tasks(campaign_id);

-- 9. TASK COMPLETIONS
create table public.task_completions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'started' check (status in ('started','submitted','approved','rejected')),
  proof jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  ledger_id uuid references public.reward_ledger(id),
  created_at timestamptz not null default now(),
  unique (task_id, user_id)
);
create index task_completions_user on public.task_completions(user_id, status);

-- 10. REFERRALS
create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_id uuid not null unique references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','valid','rejected')),
  reward_points integer not null default 0 check (reward_points >= 0),
  ledger_id uuid references public.reward_ledger(id),
  created_at timestamptz not null default now(),
  constraint referral_not_self check (referrer_id <> referred_id)
);
create index referrals_referrer on public.referrals(referrer_id);

-- 11. WITHDRAWAL REQUESTS
create table public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique default ('WD-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  user_id uuid not null references public.profiles(id) on delete restrict,
  points bigint not null check (points > 0),
  amount_usd numeric(12,2) not null check (amount_usd > 0),
  method text not null check (method in ('jazzcash','easypaisa','bank_transfer')),
  account_holder text not null,
  account_number text not null,   -- phone number / IBAN / account number ONLY. Never PINs, passwords, OTPs, CVV.
  bank_name text,
  status text not null default 'requested' check (status in
    ('requested','under_review','verification_required','approved','rejected','processing','paid')),
  admin_note text,
  payment_reference text,
  checklist jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key),
  constraint paid_needs_reference check (status <> 'paid' or (payment_reference is not null and btrim(payment_reference) <> ''))
);
-- One open request per user at a time (blocks double withdrawals)
create unique index withdrawal_one_open_per_user on public.withdrawal_requests(user_id)
  where status in ('requested','under_review','verification_required','approved','processing');
create index withdrawal_status_created on public.withdrawal_requests(status, created_at desc);

-- 12. NOTIFICATIONS
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text,
  kind text not null default 'info',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user on public.notifications(user_id, created_at desc);

-- 13. PLATFORM SETTINGS (never store secrets here: it is publicly readable)
create table public.platform_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

-- 14. ADMIN AUDIT LOGS
create table public.admin_audit_logs (
  id bigint generated always as identity primary key,
  admin_id uuid references auth.users(id),
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_created on public.admin_audit_logs(created_at desc);

-- 15. FRAUD REPORTS
create table public.fraud_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  kind text not null,
  severity text not null default 'medium' check (severity in ('low','medium','high')),
  details jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open','reviewing','dismissed','confirmed')),
  resolved_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index fraud_status on public.fraud_reports(status, created_at desc);
