-- CAN42 | 002_security_policies.sql
-- Row Level Security: users can only READ their own data. Balance changes happen only in 003 functions.

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = auth.uid() and role in ('admin','super_admin'));
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

alter table public.profiles          enable row level security;
alter table public.user_roles        enable row level security;
alter table public.wallets           enable row level security;
alter table public.reward_ledger     enable row level security;
alter table public.campaigns         enable row level security;
alter table public.videos            enable row level security;
alter table public.advertisements    enable row level security;
alter table public.tasks             enable row level security;
alter table public.task_completions  enable row level security;
alter table public.referrals         enable row level security;
alter table public.withdrawal_requests enable row level security;
alter table public.notifications     enable row level security;
alter table public.platform_settings enable row level security;
alter table public.admin_audit_logs  enable row level security;
alter table public.fraud_reports     enable row level security;

-- Start from zero privileges, then grant only what is needed.
revoke all on public.profiles, public.user_roles, public.wallets, public.reward_ledger, public.campaigns,
  public.videos, public.advertisements, public.tasks, public.task_completions, public.referrals,
  public.withdrawal_requests, public.notifications, public.platform_settings,
  public.admin_audit_logs, public.fraud_reports from anon, authenticated;

grant select on public.profiles, public.user_roles, public.wallets, public.reward_ledger, public.campaigns,
  public.videos, public.advertisements, public.tasks, public.task_completions, public.referrals,
  public.withdrawal_requests, public.notifications, public.admin_audit_logs, public.fraud_reports to authenticated;
grant select on public.platform_settings to anon, authenticated;

-- Users may change ONLY their name and mark notifications read.
grant update (full_name) on public.profiles to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Admin content management (still gated by is_admin() policies below).
grant insert, update, delete on public.campaigns, public.videos, public.advertisements, public.tasks to authenticated;
grant insert, update on public.platform_settings to authenticated;

create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy roles_select on public.user_roles for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy wallets_select on public.wallets for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy ledger_select  on public.reward_ledger for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy referrals_select on public.referrals for select to authenticated using (referrer_id = auth.uid() or public.is_admin());
create policy withdrawals_select on public.withdrawal_requests for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy completions_select on public.task_completions for select to authenticated using (user_id = auth.uid() or public.is_admin());

create policy campaigns_select on public.campaigns for select to authenticated using (status = 'active' or public.is_admin());
create policy campaigns_admin_ins on public.campaigns for insert to authenticated with check (public.is_admin());
create policy campaigns_admin_upd on public.campaigns for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy campaigns_admin_del on public.campaigns for delete to authenticated using (public.is_admin());

create policy videos_select on public.videos for select to authenticated using (exists (select 1 from public.campaigns c where c.id = campaign_id));
create policy videos_admin_ins on public.videos for insert to authenticated with check (public.is_admin());
create policy videos_admin_upd on public.videos for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy videos_admin_del on public.videos for delete to authenticated using (public.is_admin());

create policy ads_select on public.advertisements for select to authenticated using (exists (select 1 from public.campaigns c where c.id = campaign_id));
create policy ads_admin_ins on public.advertisements for insert to authenticated with check (public.is_admin());
create policy ads_admin_upd on public.advertisements for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy ads_admin_del on public.advertisements for delete to authenticated using (public.is_admin());

create policy tasks_select on public.tasks for select to authenticated using (exists (select 1 from public.campaigns c where c.id = campaign_id));
create policy tasks_admin_ins on public.tasks for insert to authenticated with check (public.is_admin());
create policy tasks_admin_upd on public.tasks for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy tasks_admin_del on public.tasks for delete to authenticated using (public.is_admin());

create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notifications_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy settings_select on public.platform_settings for select to anon, authenticated using (true);
create policy settings_admin_ins on public.platform_settings for insert to authenticated with check (public.is_admin());
create policy settings_admin_upd on public.platform_settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy audit_select on public.admin_audit_logs for select to authenticated using (public.is_admin());
create policy fraud_select on public.fraud_reports for select to authenticated using (public.is_admin());
