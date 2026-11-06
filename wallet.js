// CAN42 | wallet.js
import { supabase } from './supabase.js';
import { $, $$, escapeHtml, formatPoints, formatUsd, initProtectedPage, loadSettings, ledgerRowHtml, emptyState } from './common.js';

const setStat = (key, text) => { $$(`[data-stat="${key}"]`).forEach(el => { el.textContent = text; }); };

(async function init() {
  const session = await initProtectedPage('wallet');
  if (!session) return;
  const uid = session.user.id;
  const notices = [];
  try {
    const [wal, settings, earn] = await Promise.all([
      supabase.from('wallets').select('*').eq('user_id', uid).maybeSingle(),
      loadSettings(),
      supabase.from('reward_ledger').select('*').eq('user_id', uid)
        .in('entry_type', ['video_reward', 'ad_reward', 'referral_reward']).order('created_at', { ascending: false }).limit(10)
    ]);
    if (wal.error) throw wal.error;
    if (earn.error) throw earn.error;
    if (!wal.data) throw new Error('wallet missing');
    const w = wal.data, rate = settings.points_per_usd;

    setStat('available', formatPoints(w.available_points));
    setStat('available-usd', `Estimated value ${formatUsd(w.available_points, rate)} (${formatPoints(rate)} points = $1, demonstration rate)`);
    setStat('pending', formatPoints(w.pending_points));
    setStat('reserved', formatPoints(w.reserved_points));
    setStat('lifetime', formatPoints(w.lifetime_earned));
    setStat('withdrawn', formatPoints(w.total_withdrawn));

    const minPoints = Math.ceil(settings.min_withdrawal_usd * rate);
    const pct = Math.min(100, Math.floor((Number(w.available_points) / minPoints) * 100));
    $('#min-text').textContent = `${formatPoints(minPoints)} points (${'$' + settings.min_withdrawal_usd})`;
    $('#min-bar').setAttribute('aria-valuenow', String(pct));
    $('#min-bar span').style.width = pct + '%';
    $('#min-hint').textContent = Number(w.available_points) >= minPoints
      ? 'You have reached the minimum. Withdrawals still depend on review and funding.'
      : `${formatPoints(minPoints - Number(w.available_points))} more approved points needed to reach the minimum.`;

    $('#earnings').innerHTML = earn.data.length ? earn.data.map(ledgerRowHtml).join('')
      : emptyState('No earnings yet. Rewards appear here after you complete opportunities.');

    if (!settings.payouts_enabled) notices.push('Withdrawals are not open yet. Your points stay safe in your wallet.');
  } catch (err) {
    console.error(err);
    notices.push('We could not load your wallet. Check your connection and refresh.');
  }
  $('#notices').innerHTML = notices.map(m => `<p class="notice-box notice-info">${escapeHtml(m)}</p>`).join('');
})();
