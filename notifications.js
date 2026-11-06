// CAN42 | notifications.js
import { supabase } from './supabase.js';
import { $, $$, escapeHtml, formatDate, initProtectedPage, emptyState } from './common.js';

let uid, filter = 'all', rows = [];

function render() {
  const shown = filter === 'unread' ? rows.filter(r => !r.read_at) : rows;
  $('#n-list').innerHTML = shown.length ? shown.map(n => `
    <li class="row${n.read_at ? '' : ' unread'}">
      <div class="row-main">
        <strong>${escapeHtml(n.title)}</strong>
        ${n.body ? `<span class="row-note">${escapeHtml(n.body)}</span>` : ''}
        <span class="row-meta"><span>${escapeHtml(formatDate(n.created_at))}</span></span>
      </div>
      <div class="row-side">${n.read_at ? '' : `<button type="button" class="btn btn-ghost btn-sm" data-read="${escapeHtml(n.id)}">Mark read</button>`}</div>
    </li>`).join('') : emptyState(filter === 'unread' ? 'No unread notifications.' : 'No notifications yet.');
}
function updateDot() {
  const n = rows.filter(r => !r.read_at).length, dot = $('#unread-dot');
  if (dot) { dot.textContent = n > 99 ? '99+' : String(n); dot.hidden = n === 0; }
}
async function load() {
  const { data, error } = await supabase.from('notifications').select('id,title,body,kind,read_at,created_at')
    .eq('user_id', uid).order('created_at', { ascending: false }).limit(100);
  if (error) { console.error(error); $('#n-list').innerHTML = emptyState('We could not load notifications. Refresh and try again.'); return; }
  rows = data; render(); updateDot();
}

(async function init() {
  const session = await initProtectedPage('notifications');
  if (!session) return;
  uid = session.user.id;
  await load();

  $('#n-chips').addEventListener('click', e => {
    const b = e.target.closest('[data-filter]');
    if (!b) return;
    filter = b.dataset.filter;
    $$('#n-chips .chip').forEach(c => c.setAttribute('aria-pressed', String(c === b)));
    render();
  });
  $('#n-list').addEventListener('click', async e => {
    const b = e.target.closest('[data-read]');
    if (!b) return;
    b.disabled = true;
    const now = new Date().toISOString();
    const { error } = await supabase.from('notifications').update({ read_at: now }).eq('id', b.dataset.read).eq('user_id', uid);
    if (error) { b.disabled = false; return; }
    const row = rows.find(r => r.id === b.dataset.read);
    if (row) row.read_at = now;
    render(); updateDot();
  });
  $('#mark-all').addEventListener('click', async () => {
    const now = new Date().toISOString();
    const { error } = await supabase.from('notifications').update({ read_at: now }).eq('user_id', uid).is('read_at', null);
    if (error) return;
    rows.forEach(r => { if (!r.read_at) r.read_at = now; });
    render(); updateDot();
  });
})();
