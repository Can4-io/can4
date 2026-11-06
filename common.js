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
  hydrateIcons();
}

document.addEventListener('click', e => {
  if (e.target.closest('[data-logout]')) signOutAndGo();
});
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', renderChrome);
else renderChrome();
