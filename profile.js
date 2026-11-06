// CAN42 | profile.js - name, referral code, password, sessions. Role and status cannot be changed here (column grants + RLS).
import { supabase } from './supabase.js';
import { CONFIG } from './config.js';
import { $, $$, formatDate, setMessage, setBusy, toast, initProtectedPage } from './common.js';

const siteUrl = () => (CONFIG.SITE_URL || location.origin).replace(/\/$/, '');
function passwordProblem(pw) {
  if (pw.length < 8) return 'Use at least 8 characters.';
  if (pw.length > 72) return 'Use 72 characters or fewer.';
  if (!/[A-Za-z]/.test(pw) || !/[0-9]/.test(pw)) return 'Include at least one letter and one number.';
  return '';
}
async function copy(text, label) {
  try { await navigator.clipboard.writeText(text); toast(`${label} copied`, 'ok'); }
  catch { toast('Copy failed. Select the text and copy it manually.', 'error'); }
}

(async function init() {
  const session = await initProtectedPage('profile');
  if (!session) return;
  const uid = session.user.id;

  const { data: p, error } = await supabase.from('profiles')
    .select('full_name,email,status,referral_code,created_at').eq('id', uid).maybeSingle();
  if (error || !p) { setMessage($('#profile-form'), 'We could not load your profile. Refresh and try again.'); return; }
  $('#full_name').value = p.full_name;
  $('#email').value = p.email;
  $('#p-status').textContent = p.status.charAt(0).toUpperCase() + p.status.slice(1);
  $('#p-since').textContent = formatDate(p.created_at);
  $('#ref-code').textContent = p.referral_code;
  const link = `${siteUrl()}/register.html?ref=${encodeURIComponent(p.referral_code)}`;
  $('#ref-link').value = link;
  $('#copy-code').addEventListener('click', () => copy(p.referral_code, 'Code'));
  $('#copy-link').addEventListener('click', () => copy(link, 'Link'));

  const pf = $('#profile-form');
  pf.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(pf, '');
    const name = $('#full_name').value.trim().replace(/\s+/g, ' ');
    if (name.length < 2 || name.length > 100) return setMessage(pf, 'Enter your full name (2 to 100 characters).');
    const btn = $('button[type=submit]', pf);
    setBusy(btn, true, 'Saving...');
    const { error: err } = await supabase.from('profiles').update({ full_name: name }).eq('id', uid);
    setBusy(btn, false);
    if (err) return setMessage(pf, 'Could not save your name. Please try again.');
    $('#full_name').value = name;
    setMessage(pf, 'Saved.', 'ok');
  });

  const pw = $('#password-form');
  $('[data-show-password]', pw).addEventListener('change', e =>
    $$('input[data-pw]', pw).forEach(i => { i.type = e.target.checked ? 'text' : 'password'; }));
  pw.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(pw, '');
    const a = $('#new_password').value, b = $('#confirm_password').value;
    const problem = passwordProblem(a);
    if (problem) return setMessage(pw, problem);
    if (a !== b) return setMessage(pw, 'The two passwords do not match.');
    const btn = $('button[type=submit]', pw);
    setBusy(btn, true, 'Updating...');
    const { error: err } = await supabase.auth.updateUser({ password: a });
    setBusy(btn, false);
    if (err) return setMessage(pw, err.message);
    pw.reset();
    setMessage(pw, 'Password updated.', 'ok');
  });

  $('#logout-all').addEventListener('click', async () => {
    await supabase.auth.signOut({ scope: 'global' });
    location.href = 'login.html';
  });
})();
