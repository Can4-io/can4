-- CAN42 | 003_functions.sql
-- All balance changes live here. Browsers cannot write to wallets or reward_ledger directly.

-- ---------- internal helpers (not callable from the browser) ----------
create or replace function public.setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = p_key), p_default);
$$;

create or replace function public.setting_bool(p_key text, p_default boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = p_key), p_default);
$$;

create or replace function public.audit_log(p_action text, p_target_type text, p_target_id text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.admin_audit_logs(admin_id, action, target_type, target_id, details)
  values (auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_details,'{}'::jsonb));
$$;

-- Credit points to a user (pending or approved). Idempotent per (user, key).
create or replace function public.ledger_credit(
  p_user uuid, p_points bigint, p_type text, p_status text,
  p_source_type text, p_source_id uuid, p_key text, p_note text, p_actor uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_points <= 0 then raise exception 'Credit must be positive'; end if;
  if p_status not in ('pending','approved') then raise exception 'Invalid credit status'; end if;
  if p_type not in ('video_reward','ad_reward','referral_reward') then raise exception 'Invalid credit type'; end if;

  perform 1 from public.wallets where user_id = p_user for update;   -- serialises concurrent requests
  if not found then raise exception 'Wallet not found'; end if;

  if p_key is not null then
    select id into v_id from public.reward_ledger where user_id = p_user and idempotency_key = p_key;
    if v_id is not null then return v_id; end if;                    -- duplicate claim: return original
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

-- ---------- new user trigger ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text; v_ref text; v_referrer uuid; v_name text;
begin
  v_name := left(coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'),''), 'Member'), 100);
  if char_length(v_name) < 2 then v_name := 'Member'; end if;

  loop
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
    exit when not exists (select 1 from public.profiles where referral_code = v_code);
  end loop;

  v_ref := upper(btrim(coalesce(new.raw_user_meta_data->>'ref_code','')));
  if v_ref <> '' then
    select id into v_referrer from public.profiles where referral_code = v_ref and status = 'active';
  end if;
  if v_referrer = new.id then v_referrer := null; end if;

  insert into public.profiles(id, full_name, email, referral_code, referred_by, terms_accepted_at)
  values (new.id, v_name, lower(new.email), v_code, v_referrer,
          case when (new.raw_user_meta_data->>'terms_accepted') = 'true' then now() end);
  insert into public.wallets(user_id) values (new.id);
  if v_referrer is not null then
    insert into public.referrals(referrer_id, referred_id, status) values (v_referrer, new.id, 'pending');
  end if;
  insert into public.notifications(user_id, title, body, kind)
  values (new.id, 'Welcome to CAN42', 'Your account is ready. Verify your email to keep your account secure.', 'welcome');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- admin: approve / reject / reverse a pending reward ----------
create or replace function public.approve_ledger_entry(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reward_ledger%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into r from public.reward_ledger where id = p_id for update;
  if not found then raise exception 'Entry not found'; end if;
  if r.status <> 'pending' or r.points <= 0 or r.entry_type not in ('video_reward','ad_reward','referral_reward') then
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

create or replace function public.reject_ledger_entry(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reward_ledger%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into r from public.reward_ledger where id = p_id for update;
  if not found then raise exception 'Entry not found'; end if;
  if r.status <> 'pending' or r.points <= 0 then raise exception 'Only pending reward entries can be rejected'; end if;
  perform 1 from public.wallets where user_id = r.user_id for update;
  update public.wallets set pending_points = pending_points - r.points, updated_at = now() where user_id = r.user_id;
  update public.reward_ledger set status = 'rejected', note = coalesce(p_reason, note) where id = p_id;
  insert into public.notifications(user_id, title, body, kind)
  values (r.user_id, 'Reward not approved', coalesce(p_reason, 'A pending reward was not approved.'), 'reward');
  perform public.audit_log('reject_reward', 'reward_ledger', p_id::text, jsonb_build_object('reason', p_reason));
end $$;

create or replace function public.reverse_ledger_entry(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reward_ledger%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;
  select * into r from public.reward_ledger where id = p_id for update;
  if not found then raise exception 'Entry not found'; end if;
  if r.status <> 'approved' or r.points <= 0 then raise exception 'Only approved rewards can be reversed'; end if;
  perform 1 from public.wallets where user_id = r.user_id for update;
  if (select available_points from public.wallets where user_id = r.user_id) < r.points then
    raise exception 'User has already spent or reserved these points; resolve manually';
  end if;
  update public.wallets set available_points = available_points - r.points,
    lifetime_earned = greatest(lifetime_earned - r.points, 0), updated_at = now() where user_id = r.user_id;
  update public.reward_ledger set status = 'reversed', note = p_reason where id = p_id;
  insert into public.reward_ledger(user_id, entry_type, status, points, source_type, source_id, idempotency_key, note, created_by)
  values (r.user_id, 'reversal', 'completed', -r.points, 'reward_ledger', r.id, 'reversal:' || r.id, p_reason, auth.uid());
  insert into public.notifications(user_id, title, body, kind)
  values (r.user_id, 'Reward reversed', p_reason, 'reward');
  perform public.audit_log('reverse_reward', 'reward_ledger', p_id::text, jsonb_build_object('reason', p_reason));
end $$;

create or replace function public.admin_adjust_points(p_user uuid, p_points bigint, p_reason text, p_key text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  if p_points = 0 then raise exception 'Adjustment cannot be zero'; end if;
  if p_reason is null or btrim(p_reason) = '' then raise exception 'A reason is required'; end if;
  if p_key is null or btrim(p_key) = '' then raise exception 'Idempotency key required'; end if;
  perform 1 from public.wallets where user_id = p_user for update;
  if not found then raise exception 'Wallet not found'; end if;
  select id into v_id from public.reward_ledger where user_id = p_user and idempotency_key = p_key;
  if v_id is not null then return v_id; end if;
  if p_points < 0 and (select available_points from public.wallets where user_id = p_user) < -p_points then
    raise exception 'Adjustment would make the balance negative';
  end if;
  insert into public.reward_ledger(user_id, entry_type, status, points, source_type, idempotency_key, note, created_by)
  values (p_user, 'admin_adjustment', 'completed', p_points, 'admin', p_key, p_reason, auth.uid())
  returning id into v_id;
  update public.wallets set available_points = available_points + p_points,
    lifetime_earned = lifetime_earned + greatest(p_points, 0), updated_at = now() where user_id = p_user;
  perform public.audit_log('adjust_points', 'wallet', p_user::text, jsonb_build_object('points', p_points, 'reason', p_reason));
  return v_id;
end $$;

-- ---------- user: request a withdrawal (reserves points atomically) ----------
create or replace function public.request_withdrawal(
  p_points bigint, p_method text, p_account_holder text, p_account_number text,
  p_bank_name text, p_idempotency_key text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_id uuid; v_rate numeric; v_min bigint; v_wallet public.wallets%rowtype; v_status text;
begin
  if v_uid is null then raise exception 'Please sign in' using errcode = '42501'; end if;
  if not public.setting_bool('payouts_enabled', false) then raise exception 'Withdrawals are not open yet'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then raise exception 'Missing request key'; end if;
  if p_method not in ('jazzcash','easypaisa','bank_transfer') then raise exception 'Invalid payment method'; end if;
  if char_length(btrim(coalesce(p_account_holder,''))) not between 2 and 100 then raise exception 'Enter the account holder name'; end if;
  if coalesce(p_account_number,'') !~ '^[A-Za-z0-9 -]{6,34}$' then raise exception 'Enter a valid account or phone number'; end if;
  if p_method = 'bank_transfer' and char_length(btrim(coalesce(p_bank_name,''))) < 2 then raise exception 'Enter the bank name'; end if;

  select status into v_status from public.profiles where id = v_uid;
  if v_status is distinct from 'active' then raise exception 'Your account cannot request withdrawals'; end if;

  select * into v_wallet from public.wallets where user_id = v_uid for update;
  if not found then raise exception 'Wallet not found'; end if;

  select id into v_id from public.withdrawal_requests where user_id = v_uid and idempotency_key = p_idempotency_key;
  if v_id is not null then return v_id; end if;                      -- duplicate submit

  if exists (select 1 from public.withdrawal_requests where user_id = v_uid
             and status in ('requested','under_review','verification_required','approved','processing')) then
    raise exception 'You already have a withdrawal in progress';
  end if;

  v_rate := public.setting_num('points_per_usd', 1000);
  v_min  := ceil(public.setting_num('min_withdrawal_usd', 20) * v_rate);
  if p_points < v_min then raise exception 'Minimum withdrawal is % points', v_min; end if;
  if p_points > v_wallet.available_points then raise exception 'Not enough available points'; end if;

  update public.wallets set available_points = available_points - p_points,
    reserved_points = reserved_points + p_points, updated_at = now() where user_id = v_uid;

  insert into public.withdrawal_requests(user_id, points, amount_usd, method, account_holder, account_number, bank_name, idempotency_key)
  values (v_uid, p_points, round(p_points::numeric / v_rate, 2), p_method, btrim(p_account_holder), btrim(p_account_number),
          nullif(btrim(coalesce(p_bank_name,'')), ''), p_idempotency_key)
  returning id into v_id;

  insert into public.reward_ledger(user_id, entry_type, status, points, source_type, source_id, idempotency_key, note, created_by)
  values (v_uid, 'withdrawal_reserve', 'pending', -p_points, 'withdrawal', v_id, 'reserve:' || v_id, 'Reserved for withdrawal', v_uid);

  insert into public.notifications(user_id, title, body, kind)
  values (v_uid, 'Withdrawal submitted', 'We received your request. Status: Requested.', 'withdrawal');
  return v_id;
end $$;

-- ---------- admin: review a withdrawal ----------
-- p_action: review | need_verification | approve | reject | processing | paid
create or replace function public.review_withdrawal(
  p_id uuid, p_action text, p_note text default null, p_payment_reference text default null, p_checklist jsonb default null)
returns text language plpgsql security definer set search_path = public as $$
declare w public.withdrawal_requests%rowtype; v_new text; v_check jsonb;
begin
  if not public.is_admin() then raise exception 'Not authorized' using errcode = '42501'; end if;
  select * into w from public.withdrawal_requests where id = p_id for update;
  if not found then raise exception 'Withdrawal not found'; end if;
  if w.status in ('rejected','paid') then raise exception 'This withdrawal is already final'; end if;

  v_new := case p_action when 'review' then 'under_review' when 'need_verification' then 'verification_required'
    when 'approve' then 'approved' when 'reject' then 'rejected' when 'processing' then 'processing'
    when 'paid' then 'paid' else null end;
  if v_new is null then raise exception 'Unknown action'; end if;

  if not (
    (v_new in ('under_review','verification_required','approved') and w.status in ('requested','under_review','verification_required'))
    or (v_new = 'processing' and w.status = 'approved')
    or (v_new = 'paid' and w.status in ('approved','processing'))
    or (v_new = 'rejected' and w.status in ('requested','under_review','verification_required','approved','processing'))
  ) then raise exception 'Cannot change status from % to %', w.status, v_new; end if;

  v_check := coalesce(p_checklist, w.checklist);
  if v_new = 'approved' and not (v_check @> '{"email_verified":true,"account_details_checked":true,"reward_history_reviewed":true,"fraud_checks_done":true,"destination_confirmed":true}'::jsonb) then
    raise exception 'Complete every item in the verification checklist before approving';
  end if;
  if v_new = 'rejected' and (p_note is null or btrim(p_note) = '') then raise exception 'A rejection reason is required'; end if;
  if v_new = 'paid' and (p_payment_reference is null or btrim(p_payment_reference) = '') then
    raise exception 'Enter the real payment reference before marking as paid';
  end if;

  perform 1 from public.wallets where user_id = w.user_id for update;

  if v_new = 'rejected' then
    update public.wallets set reserved_points = reserved_points - w.points,
      available_points = available_points + w.points, updated_at = now() where user_id = w.user_id;
    insert into public.reward_ledger(user_id, entry_type, status, points, source_type, source_id, idempotency_key, note, created_by)
    values (w.user_id, 'withdrawal_release', 'completed', w.points, 'withdrawal', w.id, 'release:' || w.id, 'Withdrawal rejected: points restored', auth.uid());
    update public.reward_ledger set status = 'rejected' where idempotency_key = 'reserve:' || w.id and user_id = w.user_id;
  elsif v_new = 'paid' then
    update public.wallets set reserved_points = reserved_points - w.points,
      total_withdrawn = total_withdrawn + w.points, updated_at = now() where user_id = w.user_id;
    insert into public.reward_ledger(user_id, entry_type, status, points, source_type, source_id, idempotency_key, note, created_by)
    values (w.user_id, 'withdrawal_paid', 'completed', -w.points, 'withdrawal', w.id, 'paid:' || w.id, 'Paid. Ref: ' || btrim(p_payment_reference), auth.uid());
    update public.reward_ledger set status = 'completed' where idempotency_key = 'reserve:' || w.id and user_id = w.user_id;
  end if;

  update public.withdrawal_requests set status = v_new, checklist = v_check,
    admin_note = coalesce(nullif(btrim(coalesce(p_note,'')), ''), admin_note),
    payment_reference = case when v_new = 'paid' then btrim(p_payment_reference) else payment_reference end,
    paid_at = case when v_new = 'paid' then now() else paid_at end,
    reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_id;

  insert into public.notifications(user_id, title, body, kind)
  values (w.user_id, 'Withdrawal update: ' || initcap(replace(v_new,'_',' ')),
    case v_new when 'rejected' then 'Your points were returned. Reason: ' || p_note
               when 'paid' then 'Your payment was sent. Reference: ' || btrim(p_payment_reference)
               else 'Your withdrawal ' || w.reference || ' is now ' || replace(v_new,'_',' ') || '.' end, 'withdrawal');
  perform public.audit_log('withdrawal_' || p_action, 'withdrawal_requests', p_id::text,
    jsonb_build_object('from', w.status, 'to', v_new, 'note', p_note));
  return v_new;
end $$;

-- ---------- permissions: who may call what ----------
revoke execute on function public.setting_num(text, numeric), public.setting_bool(text, boolean),
  public.audit_log(text, text, text, jsonb),
  public.ledger_credit(uuid, bigint, text, text, text, uuid, text, text, uuid),
  public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.approve_ledger_entry(uuid), public.reject_ledger_entry(uuid, text),
  public.reverse_ledger_entry(uuid, text), public.admin_adjust_points(uuid, bigint, text, text),
  public.request_withdrawal(bigint, text, text, text, text, text),
  public.review_withdrawal(uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.approve_ledger_entry(uuid), public.reject_ledger_entry(uuid, text),
  public.reverse_ledger_entry(uuid, text), public.admin_adjust_points(uuid, bigint, text, text),
  public.request_withdrawal(bigint, text, text, text, text, text),
  public.review_withdrawal(uuid, text, text, text, jsonb) to authenticated;
