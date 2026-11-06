-- CAN42 | 004_initial_settings.sql
-- Safe starting values. Rewards and payouts are OFF until you finish launch checks.
insert into public.platform_settings(key, value, description) values
  ('points_per_usd',        '1000',  'Demonstration rate: 1,000 points = $1. Not a guaranteed cash value.'),
  ('min_withdrawal_usd',    '20',    'Minimum withdrawal in USD equivalent.'),
  ('referral_reward_points','0',     'Points per valid referral. Set above 0 only when funded.'),
  ('daily_reward_cap_points','5000', 'Maximum reward points one user can earn per day.'),
  ('rewards_enabled',       'false', 'Turn on only when campaigns are funded and legal checks are done.'),
  ('payouts_enabled',       'false', 'Turn on only after legal, tax, age and payment checks are done.'),
  ('support_email',         '"ashfaqpk.76587@gmail.com"', 'Official support email.')
on conflict (key) do nothing;
