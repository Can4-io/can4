-- CAN42 | 005_earning_and_admin.sql
-- Run ONCE in Supabase SQL Editor after 001-004. Adds earning tasks, referral review and admin tools.
-- It changes structure only; it does not delete or overwrite any existing user data.

-- ======================= A. TASKS: general (non-campaign) tasks =======================
alter table public.tasks alter column campaign_id drop not null;
alter table public.tasks add column if not exists task_type text not null default 'one_time'
  check (task_type in ('daily','one_time','special'));
alter table public.tasks add column if not exists description text;
alter table public.tasks add column if not exists requirements text;
alter table public.tasks add column if not exists deadline_at timestamptz;
alter table public.tasks add column if not exists max_completions integer check (max_completions is null or max_completions > 0);
alter table public.tasks add column if not exists completions_count integer not null default 0 check (completions_count >= 0);
alter table public.tasks add column if not exists updated_at timestamptz not null default now();
create index if not exists tasks_active_type on public.tasks(active, task_type);

-- ======================= B. TASK COMPLETIONS: one per task per period =======================
alter table public.task_completions add column if not exists period_key text not null default 'once';
alter table public.task_completions add column if not exists review_note text;
alter table public.task_completions drop constraint if exists task_completions_task_id_user_id_key;
create unique index if not exists task_completions_unique_period on public.task_completions(task_id, user_id, period_key);

-- ======================= C. LEDGER: allow task rewards =======================
alter table public.reward_ledger drop constraint if exists reward_ledger_entry_type_check;
alter table public.reward_ledger add constraint reward_ledger_entry_type_check check (entry_type in
  ('video_reward','ad_reward','referral_reward','task_reward','withdrawal_reserve','withdrawal_release','withdrawal_paid','reversal','admin_adjustment'));

-- ======================= D. POLICIES: admin writes now go through audited functions =======================
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select to authenticated using (
  public.is_admin() or (active and (campaign_id is null or exists (select 1 from public.campaigns c where c.id = campaign_id))));
drop policy if exists tasks_admin_ins on public.tasks;
drop policy if exists tasks_admin_upd on public.tasks;
drop policy if exists tasks_admin_del on public.tasks;
revoke insert, update, delete on public.tasks from authenticated;

drop policy if exists settings_admin_ins on public.platform_settings;
drop policy if exists settings_admin_upd on public.platform_settings;
revoke insert, update on public.platform_settings from authenticated;

-- ======================= E. FUNCTIONS =======================

-- E1. ledger_credit: now also accepts 'task_reward' (same signature as 003)
create or replace function public.ledger_credit(
  p_user uuid, p_points bigint, p_type text, p_status text,
  p_source_type text, p_source_id uuid, p_key text, p_note text, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_points <= 0 then raise exception 'Credit must be positive'; end if;
  if p_status not in ('pending','approved') then raise exception 'Invalid credit status'; end if;
  if p_type not in ('video_reward','ad_reward','referral_reward','task_reward') then raise exception 'Invalid credit type'; end if;
  perform 1 from public.wallets where user_id = p_user for update;
  if not found then raise exception 'Wallet not found'; end if;
  if p_key is not null then
    select id into v_id from public.reward_ledger where user_id = p_user and idempotency_key = p_key;
    if v_id is not null then return v_id; end if;
  end if;
  insert into public.reward_ledger(user_id, entry_type, status, points, source_type, source_id, idempotency_key, note, created_by)
  values (p_user, p_type, p_status, p_points, p_source_type, p_source_id, p_key, p_note, p_actor)
  returning id into v_id;
  if p_status = 'approved' then
    update public.wallets set available_points = available_points + p_points,
      lifetime_earned = lifetime_earned + p_points, updated_at = now() where user_id = p_user;
  else
    update public.wallets set pending_points = pending_points + p_points, updated_at = now() where user_id = p_user;
  end if;
  return v_id;
end $$;

-- E2. approve_ledger_entry: now also accepts 'task_reward'
create or replace function public.approve_ledger_entry(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reward_ledger%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into r from public.reward_ledger where id = p_id for update;
  if not found then raise exception 'Entry not found'; end if;
  if r.status <> 'pending' or r.points <= 0 or r.entry_type not in ('video_reward','ad_reward','referral_reward','task_reward') then
    raise exception 'Only pending reward entries can be approved';
  end if;
  perform 1 from public.wallets where user_id = r.user_id for update;
  update public.wallets set pending_points = pending_points - r.points,
    available_points = available_points + r.points, lifetime_earned = lifetime_earned + r.points,
    updated_at = now() where user_id = r.user_id;
  update public.reward_ledger set status = 'approved' where id = p_id;
  insert into public.notifications(user_id, title, body, kind)
  values (r.user_id, 'Reward approved', r.points || ' CAN42 Points are now available.', 'reward');
  perform public.audit_log('approve_reward', 'reward_ledger', p_id::text, jsonb_build_object('points', r.points, 'user_id', r.user_id));
end $$;

-- E3. submit_task: a user submits proof for a task. Creates a PENDING reward only. Never pays instantly.
create or replace function public.submit_task(p_task_id uuid, p_proof_text text, p_proof_link text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); t public.tasks%rowtype; v_status text; v_period text; v_id uuid; v_ledger uuid;
  v_cap numeric; v_today bigint; v_text text; v_link text;
begin
  if v_uid is null then raise exception 'Please sign in' using errcode = '42501'; end if;
  if not public.setting_bool('rewards_enabled', false) then raise exception 'Rewards are not open yet'; end if;
  select status into v_status from public.profiles where id = v_uid;
  if v_status is distinct from 'active' then raise exception 'Your account cannot submit tasks'; end if;

  select * into t from public.tasks where id = p_task_id for update;
  if not found or not t.active then raise exception 'This task is not available'; end if;
  if t.deadline_at is not null and t.deadline_at < now() then raise exception 'This task has expired'; end if;
  if t.campaign_id is not null and not exists (select 1 from public.campaigns c where c.id = t.campaign_id
      and c.status = 'active' and (c.starts_at is null or c.starts_at <= now()) and (c.ends_at is null or c.ends_at > now())) then
    raise exception 'This task is not available';
  end if;
  if t.max_completions is not null and t.completions_count >= t.max_completions then raise exception 'This task is full'; end if;

  v_text := btrim(coalesce(p_proof_text, ''));
  v_link := nullif(btrim(coalesce(p_proof_link, '')), '');
  if char_length(v_text) < 10 or char_length(v_text) > 1000 then raise exception 'Describe what you did (10 to 1000 characters)'; end if;
  if v_link is not null and (char_length(v_link) > 500 or v_link !~* '^https?://') then
    raise exception 'The link must start with http:// or https://';
  end if;

  v_period := case when t.task_type = 'daily' then ((now() at time zone 'utc')::date)::text else 'once' end;

  perform 1 from public.wallets where user_id = v_uid for update;   -- serialises this user's submissions
  if not found then raise exception 'Wallet not found'; end if;
  if exists (select 1 from public.task_completions where task_id = t.id and user_id = v_uid and period_key = v_period) then
    raise exception 'You have already submitted this task';
  end if;

  v_cap := public.setting_num('daily_reward_cap_points', 5000);
  select coalesce(sum(points), 0) into v_today from public.reward_ledger
   where user_id = v_uid and points > 0 and entry_type in ('video_reward','ad_reward','task_reward')
     and status in ('pending','approved')
     and created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc');
  if v_today + t.reward_points > v_cap then raise exception 'Daily reward limit reached. Try again tomorrow'; end if;

  insert into public.task_completions(task_id, user_id, status, proof, submitted_at, period_key)
  values (t.id, v_uid, 'submitted', jsonb_build_object('text', v_text, 'link', v_link), now(), v_period)
  returning id into v_id;

  v_ledger := public.ledger_credit(v_uid, t.reward_points, 'task_reward', 'pending', 'task_completion', v_id,
                                   'task:' || v_id, 'Task: ' || left(t.title, 80), v_uid);
  update public.task_completions set ledger_id = v_ledger where id = v_id;
  update public.tasks set completions_count = completions_count + 1, updated_at = now() where id = t.id;

  insert into public.notifications(user_id, title, body, kind)
  values (v_uid, 'Task submitted', 'Your submission for "' || left(t.title, 80) || '" is waiting for review.', 'reward');
  return v_id;
end $$;

-- E4. review_task_submission: admin approves or rejects. p_action = approve | reject
create or replace function public.review_task_submission(p_id uuid, p_action text, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
declare c public.task_completions%rowtype; v_title text;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into c from public.task_completions where id = p_id for update;
  if not found then raise exception 'Submission not found'; end if;
  if c.status <> 'submitted' then raise exception 'This submission was already reviewed'; end if;
  if c.ledger_id is null then raise exception 'Submission has no reward entry'; end if;
  select title into v_title from public.tasks where id = c.task_id;

  if p_action = 'approve' then
    perform public.approve_ledger_entry(c.ledger_id);
    update public.task_completions set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
      review_note = nullif(btrim(coalesce(p_note, '')), '') where id = p_id;
  elsif p_action = 'reject' then
    if p_note is null or btrim(p_note) = '' then raise exception 'A rejection reason is required'; end if;
    perform public.reject_ledger_entry(c.ledger_id, p_note);
    update public.task_completions set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(),
      review_note = btrim(p_note) where id = p_id;
    update public.tasks set completions_count = greatest(completions_count - 1, 0) where id = c.task_id;
  else
    raise exception 'Unknown action';
  end if;
  perform public.audit_log('task_' || p_action, 'task_completions', p_id::text,
    jsonb_build_object('task', v_title, 'user_id', c.user_id, 'note', p_note));
  return case p_action when 'approve' then 'approved' else 'rejected' end;
end $$;

-- E5. review_referral: admin decides. p_action = approve | reject. Reward amount comes from platform_settings.
create or replace function public.review_referral(p_id uuid, p_action text, p_note text default null)
returns text language plpgsql security definer set search_path = public, auth as $$
declare r public.referrals%rowtype; v_pts integer; v_ledger uuid; v_confirmed timestamptz; v_ref_status text;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into r from public.referrals where id = p_id for update;
  if not found then raise exception 'Referral not found'; end if;
  if r.status <> 'pending' then raise exception 'This referral was already reviewed'; end if;

  if p_action = 'approve' then
    select email_confirmed_at into v_confirmed from auth.users where id = r.referred_id;
    if v_confirmed is null then raise exception 'The referred person has not verified their email yet'; end if;
    select status into v_ref_status from public.profiles where id = r.referred_id;
    if v_ref_status is distinct from 'active' then raise exception 'The referred account is not active'; end if;
    v_pts := public.setting_num('referral_reward_points', 0)::integer;
    if v_pts > 0 then
      if not public.setting_bool('rewards_enabled', false) then
        raise exception 'Turn on rewards in Settings before approving paid referrals';
      end if;
      v_ledger := public.ledger_credit(r.referrer_id, v_pts, 'referral_reward', 'approved', 'referral', r.id,
                                       'referral:' || r.id, 'Referral reward', auth.uid());
    end if;
    update public.referrals set status = 'valid', reward_points = v_pts, ledger_id = v_ledger where id = r.id;
    insert into public.notifications(user_id, title, body, kind)
    values (r.referrer_id, 'Referral approved',
      case when v_pts > 0 then 'A friend you invited was verified. ' || v_pts || ' CAN42 Points were added.' else 'A friend you invited was verified.' end, 'referral');
  elsif p_action = 'reject' then
    if p_note is null or btrim(p_note) = '' then raise exception 'A rejection reason is required'; end if;
    update public.referrals set status = 'rejected' where id = r.id;
    insert into public.notifications(user_id, title, body, kind)
    values (r.referrer_id, 'Referral not approved', 'One of your referrals could not be approved.', 'referral');
  else
    raise exception 'Unknown action';
  end if;
  perform public.audit_log('referral_' || p_action, 'referrals', p_id::text, jsonb_build_object('note', p_note));
  return case p_action when 'approve' then 'valid' else 'rejected' end;
end $$;

-- E6. admin_set_user_status: suspend / ban / reactivate (never an admin, never yourself)
create or replace function public.admin_set_user_status(p_user uuid, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_status not in ('active','suspended','banned') then raise exception 'Invalid status'; end if;
  if p_user = auth.uid() then raise exception 'You cannot change your own account status'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user) then raise exception 'Administrator accounts cannot be changed here'; end if;
  if p_status <> 'active' and (p_reason is null or btrim(p_reason) = '') then raise exception 'A reason is required'; end if;
  update public.profiles set status = p_status, updated_at = now() where id = p_user;
  if not found then raise exception 'User not found'; end if;
  insert into public.notifications(user_id, title, body, kind)
  values (p_user, case p_status when 'active' then 'Account reactivated' else 'Account ' || p_status end,
          case p_status when 'active' then 'Your account is active again.' else 'Please contact support. Reason: ' || btrim(p_reason) end, 'security');
  perform public.audit_log('user_' || p_status, 'profiles', p_user::text, jsonb_build_object('reason', p_reason));
end $$;

-- E7. admin_update_setting: validated, audited. Turning rewards/payouts ON needs p_confirm = 'ENABLE'; payouts need a super_admin.
create or replace function public.admin_update_setting(p_key text, p_value jsonb, p_confirm text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_num numeric;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_key not in ('points_per_usd','min_withdrawal_usd','referral_reward_points','daily_reward_cap_points','rewards_enabled','payouts_enabled','support_email') then
    raise exception 'Unknown setting';
  end if;
  if p_key in ('points_per_usd','min_withdrawal_usd','referral_reward_points','daily_reward_cap_points') then
    if jsonb_typeof(p_value) <> 'number' then raise exception 'A number is required'; end if;
    v_num := (p_value #>> '{}')::numeric;
    if p_key in ('points_per_usd','min_withdrawal_usd') and (v_num <= 0 or v_num > 1000000) then raise exception 'Value out of range'; end if;
    if p_key in ('referral_reward_points','daily_reward_cap_points') and (v_num < 0 or v_num > 10000000 or v_num <> trunc(v_num)) then
      raise exception 'Enter a whole number from 0 to 10,000,000';
    end if;
  elsif p_key in ('rewards_enabled','payouts_enabled') then
    if jsonb_typeof(p_value) <> 'boolean' then raise exception 'On or off is required'; end if;
    if (p_value #>> '{}')::boolean then
      if p_confirm is distinct from 'ENABLE' then raise exception 'Type ENABLE to confirm'; end if;
      if p_key = 'payouts_enabled' and not exists (select 1 from public.user_roles where user_id = auth.uid() and role = 'super_admin') then
        raise exception 'Only a super administrator can enable payouts';
      end if;
    end if;
  elsif p_key = 'support_email' then
    if jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' or char_length(p_value #>> '{}') > 254 then
      raise exception 'Enter a valid email address';
    end if;
  end if;
  insert into public.platform_settings(key, value, updated_by, updated_at) values (p_key, p_value, auth.uid(), now())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  perform public.audit_log('setting_update', 'platform_settings', p_key, jsonb_build_object('value', p_value));
end $$;

-- E8. admin_save_task: create (p_id null) or edit a task. Tasks are archived (active = false), never deleted.
create or replace function public.admin_save_task(
  p_id uuid, p_title text, p_description text, p_requirements text, p_instructions text,
  p_task_type text, p_reward integer, p_deadline timestamptz, p_max integer, p_active boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if char_length(btrim(coalesce(p_title,''))) not between 3 and 150 then raise exception 'Title must be 3 to 150 characters'; end if;
  if p_task_type not in ('daily','one_time','special') then raise exception 'Invalid task type'; end if;
  if p_reward is null or p_reward < 1 or p_reward > 1000000 then raise exception 'Reward must be 1 to 1,000,000 points'; end if;
  if p_max is not null and p_max < 1 then raise exception 'Maximum completions must be at least 1'; end if;
  if char_length(coalesce(p_description,'')) > 2000 or char_length(coalesce(p_requirements,'')) > 2000 or char_length(coalesce(p_instructions,'')) > 2000 then
    raise exception 'Text fields are limited to 2000 characters';
  end if;
  if p_id is null then
    insert into public.tasks(title, description, requirements, instructions, task_type, reward_points, deadline_at, max_completions, active)
    values (btrim(p_title), nullif(btrim(coalesce(p_description,'')),''), nullif(btrim(coalesce(p_requirements,'')),''),
            nullif(btrim(coalesce(p_instructions,'')),''), p_task_type, p_reward, p_deadline, p_max, coalesce(p_active, true))
    returning id into v_id;
    perform public.audit_log('task_create', 'tasks', v_id::text, jsonb_build_object('title', p_title, 'reward', p_reward));
  else
    update public.tasks set title = btrim(p_title), description = nullif(btrim(coalesce(p_description,'')),''),
      requirements = nullif(btrim(coalesce(p_requirements,'')),''), instructions = nullif(btrim(coalesce(p_instructions,'')),''),
      task_type = p_task_type, reward_points = p_reward, deadline_at = p_deadline, max_completions = p_max,
      active = coalesce(p_active, true), updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Task not found'; end if;
    perform public.audit_log('task_update', 'tasks', v_id::text, jsonb_build_object('title', p_title, 'reward', p_reward, 'active', p_active));
  end if;
  return v_id;
end $$;

-- E9. admin_list_users: profiles + email verification + balances (admin only)
create or replace function public.admin_list_users(p_search text default null, p_limit integer default 25, p_offset integer default 0)
returns table(id uuid, full_name text, email text, status text, created_at timestamptz, email_verified boolean,
              last_sign_in_at timestamptz, available_points bigint, pending_points bigint, lifetime_earned bigint, has_admin_role boolean)
language plpgsql security definer set search_path = public, auth as $$
#variable_conflict use_column
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  return query
  select p.id, p.full_name, p.email, p.status, p.created_at, (u.email_confirmed_at is not null), u.last_sign_in_at,
         coalesce(w.available_points, 0), coalesce(w.pending_points, 0), coalesce(w.lifetime_earned, 0),
         exists (select 1 from public.user_roles r where r.user_id = p.id)
  from public.profiles p
  join auth.users u on u.id = p.id
  left join public.wallets w on w.user_id = p.id
  where p_search is null or btrim(p_search) = ''
     or position(lower(btrim(p_search)) in lower(p.email)) > 0
     or position(lower(btrim(p_search)) in lower(p.full_name)) > 0
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0);
end $$;

-- E10. admin_dashboard_stats: all headline numbers in one call (admin only)
create or replace function public.admin_dashboard_stats() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  return jsonb_build_object(
    'total_users',           (select count(*) from public.profiles),
    'active_users',          (select count(*) from public.profiles where status = 'active'),
    'active_30d',            (select count(*) from auth.users where last_sign_in_at > now() - interval '30 days'),
    'suspended_users',       (select count(*) from public.profiles where status <> 'active'),
    'pending_verifications', (select count(*) from auth.users where email_confirmed_at is null),
    'points_issued',         (select coalesce(sum(lifetime_earned), 0) from public.wallets),
    'points_pending',        (select coalesce(sum(pending_points), 0) from public.wallets),
    'submissions_pending',   (select count(*) from public.task_completions where status = 'submitted'),
    'tasks_approved',        (select count(*) from public.task_completions where status = 'approved'),
    'tasks_rejected',        (select count(*) from public.task_completions where status = 'rejected'),
    'active_tasks',          (select count(*) from public.tasks where active),
    'referrals_pending',     (select count(*) from public.referrals where status = 'pending'),
    'withdrawals_pending',   (select count(*) from public.withdrawal_requests where status in ('requested','under_review','verification_required')),
    'withdrawals_approved',  (select count(*) from public.withdrawal_requests where status in ('approved','processing')),
    'withdrawals_paid',      (select count(*) from public.withdrawal_requests where status = 'paid'),
    'fraud_open',            (select count(*) from public.fraud_reports where status in ('open','reviewing'))
  );
end $$;

-- ======================= F. WHO MAY CALL WHAT =======================
revoke execute on function
  public.submit_task(uuid, text, text),
  public.review_task_submission(uuid, text, text),
  public.review_referral(uuid, text, text),
  public.admin_set_user_status(uuid, text, text),
  public.admin_update_setting(text, jsonb, text),
  public.admin_save_task(uuid, text, text, text, text, text, integer, timestamptz, integer, boolean),
  public.admin_list_users(text, integer, integer),
  public.admin_dashboard_stats() from public, anon;
grant execute on function
  public.submit_task(uuid, text, text),
  public.review_task_submission(uuid, text, text),
  public.review_referral(uuid, text, text),
  public.admin_set_user_status(uuid, text, text),
  public.admin_update_setting(text, jsonb, text),
  public.admin_save_task(uuid, text, text, text, text, text, integer, timestamptz, integer, boolean),
  public.admin_list_users(text, integer, integer),
  public.admin_dashboard_stats() to authenticated;
