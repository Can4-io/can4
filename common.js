// CAN42 | common.js - shared helpers, header/footer, icons, toasts.
import { CONFIG } from './config.js';
import { supabase, isConfigured } from './supabase.js';

export const $ = (s, r = document) => r.querySelector(s);
export const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

export function escapeHtml(v) {
  return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const ICONS = {
  play: '<path d="M7 4.5v15l12-7.5z"/>',
  megaphone: '<path d="M3 11v2a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1z"/><path d="M15.5 8.5a5 5 0 0 1 0 7"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M16 4.6a3.5 3.5 0 0 1 0 6.8M18 14.3c2.2.7 3.5 2.6 3.5 5.7"/>',
  coin: '<circle cx="12" cy="12" r="9"/><path d="M9 9.5h4.5a1.8 1.8 0 0 1 0 3.5H10.5a1.8 1.8 0 0 0 0 3.5H15M12 7v2M12 16.5v2"/>',
  wallet: '<path d="M3 7a2 2 0 0 1 2-2h12v4"/><path d="M3 7v10a2 2 0 0 0 2 2h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1H5a2 2 0 0 1-2-1z"/><circle cx="16.5" cy="14" r="1"/>',
  support: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.5"/><path d="M5.6 5.6l3.9 3.9M14.5 14.5l3.9 3.9M18.4 5.6l-3.9 3.9M9.5 14.5l-3.9 3.9"/>',
  shield: '<path d="M12 3l8 3v6c0 4.5-3.2 7.8-8 9-4.8-1.2-8-4.5-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
  lock: '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>'
};
export function icon(name) {
  return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;
}
export function hydrateIcons(root = document) {
  $$('[data-icon]', root).forEach(el => { el.innerHTML = icon(el.dataset.icon); });
}

export function toast(message, type = 'info') {
  let box = $('#toasts');
  if (!box) { box = document.createElement('div'); box.id = 'toasts'; box.setAttribute('aria-live', 'polite'); document.body.appendChild(box); }
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.textContent = message;
  box.appendChild(t);
  setTimeout(() => t.remove(), 4500);
}

export function setMessage(form, text, type = 'error') {
  const box = $('.form-msg', form);
  if (!box) return;
  box.textContent = text || '';
  box.className = 'form-msg' + (text ? ` is-${type}` : '');
}
export function setBusy(btn, busy, label) {
  if (!btn) return;
  if (busy) { btn.dataset.label = btn.textContent; btn.textContent = label || 'Please wait...'; }
  else if (btn.dataset.label) btn.textContent = btn.dataset.label;
  btn.disabled = busy;
}

export const formatPoints = n => Number(n || 0).toLocaleString('en-US');
export const formatUsd = (points, rate) => `$${(Number(points || 0) / (rate || 1000)).toFixed(2)}`;

// Only allow same-site relative redirects (blocks open-redirect tricks).
export function safeRedirectTarget(raw, fallback = CONFIG.POST_LOGIN_PAGE) {
  if (!raw || !/^[a-z0-9\-_/]+\.html$/i.test(raw) || raw.startsWith('//')) return fallback;
  return raw;
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}
// Call at the top of protected pages (Part 2 onward).
export async function requireAuth() {
  const session = await getSession();
  if (!session) { location.replace(`login.html?next=${encodeURIComponent(location.pathname.split('/').pop())}`); return null; }
  return session;
}
export async function signOutAndGo() {
  await supabase.auth.signOut();
  location.href = 'index.html';
}

const NAV = [
  ['home', 'Home', 'index.html'], ['earn', 'Earn', 'earn.html'], ['videos', 'Videos', 'videos.html'],
  ['referrals', 'Referrals', 'referrals.html'], ['wallet', 'Wallet', 'wallet.html'],
  ['about', 'About', 'about.html'], ['faq', 'FAQ', 'faq.html'], ['contact', 'Contact', 'support.html']
];

export async function renderChrome() {
  const page = document.body.dataset.page || '';
  const session = isConfigured ? await getSession() : null;
  const links = NAV.map(([id, label, href]) =>
    `<a href="${href}"${id === page ? ' aria-current="page"' : ''}>${label}</a>`).join('');
  const authLinks = session
    ? `<a href="${CONFIG.POST_LOGIN_PAGE}">Dashboard</a><button type="button" class="btn btn-light btn-sm" data-logout>Log out</button>`
    : `<a href="login.html"${page === 'login' ? ' aria-current="page"' : ''}>Login</a><a class="btn btn-primary btn-sm" href="register.html">Register</a>`;

  const header = $('#site-header');
  if (header) {
    header.innerHTML = `
    <header class="site-header">
      <div class="container header-inner">
        <a class="brand" href="index.html" aria-label="CAN42 home"><img src="assets/images/logo.svg" alt="" width="36" height="36"><span>CAN42</span></a>
        <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="main-nav" aria-label="Open menu"><span data-icon="menu"></span></button>
        <nav class="nav" id="main-nav" aria-label="Main">${links}<span class="nav-auth">${authLinks}</span></nav>
      </div>
    </header>`;
    const toggle = $('.nav-toggle', header), nav = $('#main-nav', header);
    toggle.addEventListener('click', () => {
      const open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open);
      toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
      $('[data-icon]', toggle).innerHTML = icon(open ? 'x' : 'menu');
    });
  }

  const footer = $('#site-footer');
  if (footer) {
    footer.innerHTML = `
    <footer class="site-footer">
      <div class="container footer-grid">
        <div>
          <a class="brand" href="index.html"><img src="assets/images/logo.svg" alt="" width="32" height="32"><span>CAN42</span></a>
          <p class="footer-note">Watch. Earn. Connect.</p>
          <p class="footer-note">Support: <a href="mailto:${CONFIG.SUPPORT_EMAIL}">${CONFIG.SUPPORT_EMAIL}</a></p>
        </div>
        <nav aria-label="Company"><h4>Company</h4><a href="about.html">About</a><a href="support.html">Contact</a><a href="faq.html">FAQ</a></nav>
        <nav aria-label="Legal"><h4>Policies</h4><a href="terms.html">Terms</a><a href="privacy.html">Privacy</a><a href="reward-policy.html">Reward Policy</a><a href="withdrawal-policy.html">Withdrawal Policy</a></nav>
      </div>
      <div class="container footer-legal">
        CAN42 Points are promotional rewards, not money held in a bank account, and are not guaranteed income. Rewards depend on funded campaigns.
        CAN42 is not a bank and makes no claim of licensing, certification or regulatory approval.
      </div>
    </footer>`;
  }

  if (!isConfigured) {
    const bar = document.createElement('div');
    bar.className = 'config-bar';
    bar.textContent = 'Setup needed: add your Supabase URL and anon key in assets/js/config.js (see SETUP.md).';
    document.body.prepend(bar);
  }
  rewritePendingLinks();
  hydrateIcons();
}

document.addEventListener('click', e => {
  if (e.target.closest('[data-logout]')) signOutAndGo();
});
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', renderChrome);
else renderChrome();

// =====================================================================
// Part 2 additions (helpers shared by the signed-in pages)
// =====================================================================

// Pages that do not exist yet are sent to coming-soon.html instead of a broken link.
// When a later part adds a page, delete its name from this list.
const PENDING_PAGES = ['earn', 'videos', 'advertisements', 'referrals', 'support', 'about', 'faq',
  'terms', 'privacy', 'reward-policy', 'withdrawal-policy'];

export function rewritePendingLinks(root = document) {
  $$('a[href]', root).forEach(a => {
    const m = /^([a-z0-9-]+)\.html(?:[?#].*)?$/i.exec(a.getAttribute('href') || '');
    if (m && PENDING_PAGES.includes(m[1].toLowerCase())) {
      a.setAttribute('href', `coming-soon.html?page=${encodeURIComponent(m[1].toLowerCase())}`);
    }
  });
}

export const TYPE_LABELS = {
  video_reward: 'Video reward', ad_reward: 'Advertisement reward', referral_reward: 'Referral reward',
  withdrawal_reserve: 'Withdrawal (reserved)', withdrawal_release: 'Withdrawal (points returned)',
  withdrawal_paid: 'Withdrawal (paid)', reversal: 'Reversal', admin_adjustment: 'Admin adjustment'
};
export const STATUS_LABELS = {
  pending: 'Pending', approved: 'Approved', rejected: 'Rejected', completed: 'Completed', reversed: 'Reversed',
  requested: 'Requested', under_review: 'Under review', verification_required: 'Verification required',
  processing: 'Processing', paid: 'Paid'
};
export const statusBadge = s =>
  `<span class="badge badge-${escapeHtml(s)}">${escapeHtml(STATUS_LABELS[s] || s)}</span>`;
export function formatDate(iso) {
  try { return new Date(iso).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }); } catch { return ''; }
}
export const emptyState = text => `<p class="empty">${escapeHtml(text)}</p>`;
export const maskAccount = v => { const s = String(v || ''); return s.length > 4 ? '\u2022\u2022\u2022\u2022 ' + escapeHtml(s.slice(-4)) : '\u2022\u2022\u2022\u2022'; };

export function ledgerRowHtml(r) {
  const pts = Number(r.points);
  return `<li class="row">
    <div class="row-main">
      <strong>${escapeHtml(TYPE_LABELS[r.entry_type] || r.entry_type)}</strong>
      <span class="row-meta"><span>${escapeHtml(r.reference)}</span><span>${escapeHtml(formatDate(r.created_at))}</span></span>
      ${r.note ? `<span class="row-note">${escapeHtml(r.note)}</span>` : ''}
    </div>
    <div class="row-side"><span class="pts ${pts > 0 ? 'pos' : 'neg'}">${pts > 0 ? '+' : ''}${formatPoints(pts)}</span>${statusBadge(r.status)}</div>
  </li>`;
}
const METHOD_LABELS = { jazzcash: 'JazzCash', easypaisa: 'Easypaisa', bank_transfer: 'Bank transfer' };
export const methodLabel = m => METHOD_LABELS[m] || m;
export function withdrawalRowHtml(w) {
  const extra = w.status === 'paid' && w.payment_reference ? `Payment reference: ${w.payment_reference}`
    : (['rejected', 'verification_required'].includes(w.status) && w.admin_note ? w.admin_note : '');
  return `<li class="row">
    <div class="row-main">
      <strong>${escapeHtml(methodLabel(w.method))}</strong>
      <span class="row-meta"><span>${escapeHtml(w.reference)}</span><span>${escapeHtml(formatDate(w.created_at))}</span></span>
      ${extra ? `<span class="row-note">${escapeHtml(extra)}</span>` : ''}
    </div>
    <div class="row-side"><span class="pts">${formatPoints(w.points)}</span><span class="row-usd">$${Number(w.amount_usd).toFixed(2)}</span>${statusBadge(w.status)}</div>
  </li>`;
}

// Public platform settings (rate, minimum, on/off switches). Falls back to SAFE defaults (everything off).
export async function loadSettings() {
  const s = { points_per_usd: 1000, min_withdrawal_usd: 20, payouts_enabled: false, rewards_enabled: false, support_email: CONFIG.SUPPORT_EMAIL };
  const { data, error } = await supabase.from('platform_settings').select('key,value');
  if (error || !data) return s;
  data.forEach(r => { s[r.key] = r.value; });
  s.points_per_usd = Number(s.points_per_usd) > 0 ? Number(s.points_per_usd) : 1000;
  s.min_withdrawal_usd = Number(s.min_withdrawal_usd) > 0 ? Number(s.min_withdrawal_usd) : 20;
  s.payouts_enabled = s.payouts_enabled === true || s.payouts_enabled === 'true';
  s.rewards_enabled = s.rewards_enabled === true || s.rewards_enabled === 'true';
  return s;
}

const APP_NAV = [
  ['dashboard', 'Dashboard', 'dashboard.html'], ['wallet', 'Wallet', 'wallet.html'],
  ['transactions', 'Transactions', 'transactions.html'], ['withdrawals', 'Withdrawals', 'withdrawals.html'],
  ['notifications', 'Notifications', 'notifications.html'], ['profile', 'Profile', 'profile.html']
];
export async function renderAppNav(active, uid) {
  const box = $('#app-nav');
  if (!box) return;
  box.innerHTML = `<div class="container"><nav class="app-nav" aria-label="Account">${APP_NAV.map(([id, label, href]) =>
    `<a href="${href}"${id === active ? ' aria-current="page"' : ''}>${label}${id === 'notifications' ? '<span class="dot" id="unread-dot" hidden></span>' : ''}</a>`).join('')}</nav></div>`;
  if (uid) {
    const { count } = await supabase.from('notifications').select('id', { count: 'exact', head: true }).eq('user_id', uid).is('read_at', null);
    const dot = $('#unread-dot');
    if (dot && count > 0) { dot.textContent = count > 99 ? '99+' : String(count); dot.hidden = false; }
  }
}

// Every signed-in page starts with this. Returns the session, or null (and redirects to login).
export async function initProtectedPage(active) {
  const session = await requireAuth();
  if (!session) return null;
  supabase.auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT') location.replace('login.html'); });
  await renderAppNav(active, session.user.id);
  const main = $('#main');
  if (main) main.hidden = false;
  return session;
}

// Turn a database error into a short, safe message for the person.
export function friendlyError(error) {
  if (!error) return '';
  if (error.code === '23505') return 'You already have a withdrawal in progress.';
  if (error.code === 'P0001' || error.code === '42501') return error.message;   // our own readable messages
  return 'Something went wrong. Please try again, or contact support.';
}
