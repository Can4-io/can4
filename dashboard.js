// CAN42 | dashboard.js - real values only, read through Row Level Security.
import { supabase } from './supabase.js';
import { $, $$, escapeHtml, formatPoints, formatUsd, initProtectedPage, loadSettings,
  ledgerRowHtml, withdrawalRowHtml, emptyState } from './common.js';

const setStat = (key, text) => { $$(`[data-stat="${key}"]`).forEach(el => { el.textContent = text; }); };

(async function init() {
  const session = await initProtectedPage('dashboard');
  if (!session) return;
  const uid = session.user.id;
  const notices = [];
  try {
    // Always filter by the signed-in user id (admins can read all rows, so RLS alone is not enough for "my" views).
    const [prof, wal, settings, refAll, refValid, done, ledger, wds] = await Promise.all([
      supabase.from('profiles').select('full_name,status').eq('id', uid).maybeSingle(),
      supabase.from('wallets').select('*').eq('user_id', uid).maybeSingle(),
      loadSettings(),
      supabase.from('referrals').select('id', { count: 'exact', head: true }).eq('referrer_id', uid),
      supabase.from('referrals').select('id', { count: 'exact', head: true }).eq('referrer_id', uid).eq('status', 'valid'),
      supabase.from('task_completions').select('id', { count: 'exact', head: true }).eq('user_id', uid).eq('status', 'approved'),
      supabase.from('reward_ledger').select('*').eq('user_id', uid).order('created_at', { ascending: false }).limit(5),
      supabase.from('withdrawal_requests').select('id,reference,points,amount_usd,method,status,created_at,admin_note,payment_reference')
        .eq('user_id', uid).order('created_at', { ascending: false }).limit(3)
    ]);
    for (const r of [prof, wal, refAll, refValid, done, ledger, wds]) if (r.error) throw r.error;

    const first = (prof.data?.full_name || '').split(' ')[0];
    $('#welcome').textContent = first ? `Welcome, ${first}` : 'Welcome';

    if (prof.data && prof.data.status !== 'active') notices.push(['warn', `Your account is ${prof.data.status}. Contact support to find out why.`]);
    if (!settings.rewards_enabled) notices.push(['info', 'Rewards are not open yet. Opportunities will appear here once campaigns are funded and launch checks are complete.']);
    if (!settings.payouts_enabled) notices.push(['info', 'Withdrawals are not open yet. Your points stay safe in your wallet.']);

    if (!wal.data) {
      notices.push(['warn', 'Your wallet could not be found. Please contact support.']);
    } else {
      const w = wal.data;
      setStat('available', formatPoints(w.available_points));
      setStat('available-sub', `About ${formatUsd(w.available_points, settings.points_per_usd)} at the current rate`);
      setStat('pending', formatPoints(w.pending_points));
      setStat('lifetime', formatPoints(w.lifetime_earned));
    }
    setStat('completed', formatPoints(done.count));
    setStat('referrals', formatPoints(refValid.count));
    setStat('referrals-sub', `${formatPoints(refAll.count)} signed up with your code`);

    $('#recent-tx').innerHTML = ledger.data.length ? ledger.data.map(ledgerRowHtml).join('')
      : emptyState('No transactions yet. They will appear here when you earn or withdraw points.');
    $('#recent-wd').innerHTML = wds.data.length ? wds.data.map(withdrawalRowHtml).join('')
      : emptyState('No withdrawal requests yet.');
  } catch (err) {
    console.error(err);
    notices.push(['warn', 'We could not load your dashboard. Check your connection and refresh.']);
  }
  $('#notices').innerHTML = notices.map(([t, m]) => `<p class="notice-box notice-${t}">${escapeHtml(m)}</p>`).join('');
})();
