// CAN42 | transactions.js - filterable, paged ledger history.
import { supabase } from './supabase.js';
import { $, $$, initProtectedPage, ledgerRowHtml, emptyState, formatPoints } from './common.js';

const PAGE = 20;
const GROUPS = {
  earnings: ['video_reward', 'ad_reward', 'referral_reward'],
  withdrawals: ['withdrawal_reserve', 'withdrawal_release', 'withdrawal_paid'],
  other: ['reversal', 'admin_adjustment']
};
let uid, status = 'all', group = 'all', offset = 0, token = 0;

async function load(reset) {
  const my = ++token;
  const list = $('#tx-list'), more = $('#load-more');
  if (reset) { offset = 0; list.innerHTML = '<li class="empty">Loading...</li>'; more.hidden = true; }
  let q = supabase.from('reward_ledger').select('*', { count: 'exact' }).eq('user_id', uid)
    .order('created_at', { ascending: false }).range(offset, offset + PAGE - 1);
  if (status !== 'all') q = q.eq('status', status);
  if (group !== 'all') q = q.in('entry_type', GROUPS[group]);
  const { data, count, error } = await q;
  if (my !== token) return;                      // a newer filter click replaced this request
  if (error) { console.error(error); list.innerHTML = emptyState('We could not load transactions. Refresh and try again.'); return; }
  if (reset) list.innerHTML = '';
  if (reset && !data.length) list.innerHTML = emptyState('No transactions match these filters.');
  list.insertAdjacentHTML('beforeend', data.map(ledgerRowHtml).join(''));
  offset += data.length;
  more.hidden = offset >= count;
  $('#tx-count').textContent = count ? `Showing ${formatPoints(offset)} of ${formatPoints(count)}` : '';
}

(async function init() {
  const session = await initProtectedPage('transactions');
  if (!session) return;
  uid = session.user.id;
  $('#status-chips').addEventListener('click', e => {
    const b = e.target.closest('[data-status]');
    if (!b) return;
    status = b.dataset.status;
    $$('#status-chips .chip').forEach(c => c.setAttribute('aria-pressed', String(c === b)));
    load(true);
  });
  $('#group').addEventListener('change', e => { group = e.target.value in GROUPS || e.target.value === 'all' ? e.target.value : 'all'; load(true); });
  $('#load-more').addEventListener('click', () => load(false));
  load(true);
})();
