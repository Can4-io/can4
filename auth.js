// CAN42 | auth.js - registration, login, forgot/reset password. Passwords are handled only by Supabase Auth.
import { supabase, isConfigured } from './supabase.js';
import { CONFIG } from './config.js';
import { $, setMessage, setBusy, safeRedirectTarget, getSession } from './common.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const siteUrl = () => (CONFIG.SITE_URL || location.origin).replace(/\/$/, '');
const page = document.body.dataset.page;

function passwordProblem(pw) {
  if (pw.length < 8) return 'Use at least 8 characters.';
  if (pw.length > 72) return 'Use 72 characters or fewer.';
  if (!/[A-Za-z]/.test(pw) || !/[0-9]/.test(pw)) return 'Include at least one letter and one number.';
  return '';
}
function wireShowPassword(form) {
  const cb = $('[data-show-password]', form);
  if (cb) cb.addEventListener('change', () => form.querySelectorAll('input[data-pw]').forEach(i => { i.type = cb.checked ? 'text' : 'password'; }));
}
function notConfigured(form) {
  if (isConfigured) return false;
  setMessage(form, 'This site is not connected to Supabase yet. Follow SETUP.md, step 3.');
  return true;
}

// ----- Register -----
async function initRegister() {
  const form = $('#register-form');
  if (!form) return;
  wireShowPassword(form);
  const params = new URLSearchParams(location.search);
  const ref = (params.get('ref') || sessionStorage.getItem('can42_ref') || '').trim();
  if (/^[A-Za-z0-9]{4,16}$/.test(ref)) { sessionStorage.setItem('can42_ref', ref); form.referral.value = ref.toUpperCase(); }

  form.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(form, '');
    if (notConfigured(form)) return;
    const name = form.full_name.value.trim().replace(/\s+/g, ' ');
    const email = form.email.value.trim().toLowerCase();
    const pw = form.password.value, pw2 = form.confirm.value;
    const code = form.referral.value.trim().toUpperCase();
    if (name.length < 2 || name.length > 100) return setMessage(form, 'Enter your full name (2 to 100 characters).');
    if (!EMAIL_RE.test(email)) return setMessage(form, 'Enter a valid email address.');
    const pwErr = passwordProblem(pw);
    if (pwErr) return setMessage(form, pwErr);
    if (pw !== pw2) return setMessage(form, 'The two passwords do not match.');
    if (code && !/^[A-Za-z0-9]{4,16}$/.test(code)) return setMessage(form, 'The referral code format is not valid.');
    if (!form.terms.checked) return setMessage(form, 'Accept the Terms and Privacy Policy to continue.');

    const btn = $('button[type=submit]', form);
    setBusy(btn, true, 'Creating account...');
    const { data, error } = await supabase.auth.signUp({
      email, password: pw,
      options: { emailRedirectTo: `${siteUrl()}/login.html?verified=1`, data: { full_name: name, ref_code: code, terms_accepted: true } }
    });
    setBusy(btn, false);
    if (error) return setMessage(form, error.message.includes('already') ? 'An account with this email may already exist. Try logging in.' : error.message);
    sessionStorage.removeItem('can42_ref');
    if (data.session) { location.href = CONFIG.POST_LOGIN_PAGE; return; }
    form.hidden = true;
    $('#register-done').hidden = false;
    $('#done-email').textContent = email;
  });
}

// ----- Login -----
async function initLogin() {
  const form = $('#login-form');
  if (!form) return;
  wireShowPassword(form);
  const params = new URLSearchParams(location.search);
  if (params.get('verified')) setMessage(form, 'Email verified. You can log in now.', 'ok');
  if (params.get('reset')) setMessage(form, 'Password updated. Log in with your new password.', 'ok');
  const resend = $('#resend-verification');

  form.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(form, ''); resend.hidden = true;
    if (notConfigured(form)) return;
    const email = form.email.value.trim().toLowerCase();
    if (!EMAIL_RE.test(email) || !form.password.value) return setMessage(form, 'Enter your email and password.');
    const btn = $('button[type=submit]', form);
    setBusy(btn, true, 'Logging in...');
    const { error } = await supabase.auth.signInWithPassword({ email, password: form.password.value });
    setBusy(btn, false);
    if (error) {
      if (/not confirmed/i.test(error.message)) { resend.hidden = false; return setMessage(form, 'Please verify your email first. Check your inbox.'); }
      return setMessage(form, 'Incorrect email or password.');   // generic on purpose
    }
    location.href = safeRedirectTarget(params.get('next'));
  });

  resend.addEventListener('click', async () => {
    const email = form.email.value.trim().toLowerCase();
    if (!EMAIL_RE.test(email)) return setMessage(form, 'Enter your email above first.');
    const { error } = await supabase.auth.resend({ type: 'signup', email, options: { emailRedirectTo: `${siteUrl()}/login.html?verified=1` } });
    setMessage(form, error ? error.message : 'Verification email sent. Check your inbox and spam folder.', error ? 'error' : 'ok');
  });
}

// ----- Forgot password -----
function initForgot() {
  const form = $('#forgot-form');
  if (!form) return;
  form.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(form, '');
    if (notConfigured(form)) return;
    const email = form.email.value.trim().toLowerCase();
    if (!EMAIL_RE.test(email)) return setMessage(form, 'Enter a valid email address.');
    const btn = $('button[type=submit]', form);
    setBusy(btn, true, 'Sending...');
    await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${siteUrl()}/reset-password.html` });
    setBusy(btn, false);
    // Same message whether or not the email exists (prevents account discovery).
    setMessage(form, 'If that email has an account, a reset link is on its way.', 'ok');
  });
}

// ----- Reset password (opened from the email link) -----
async function initReset() {
  const form = $('#reset-form');
  if (!form) return;
  wireShowPassword(form);
  await new Promise(r => setTimeout(r, 600));     // let supabase-js read the link token
  if (!(await getSession())) { form.hidden = true; $('#reset-invalid').hidden = false; return; }
  form.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(form, '');
    const pw = form.password.value;
    const err = passwordProblem(pw);
    if (err) return setMessage(form, err);
    if (pw !== form.confirm.value) return setMessage(form, 'The two passwords do not match.');
    const btn = $('button[type=submit]', form);
    setBusy(btn, true, 'Saving...');
    const { error } = await supabase.auth.updateUser({ password: pw });
    setBusy(btn, false);
    if (error) return setMessage(form, error.message);
    await supabase.auth.signOut();
    location.href = 'login.html?reset=1';
  });
}

(async function init() {
  if (isConfigured && ['login', 'register'].includes(page) && (await getSession()) && !new URLSearchParams(location.search).get('verified')) {
    location.replace(CONFIG.POST_LOGIN_PAGE); return;
  }
  initRegister(); initLogin(); initForgot(); initReset();
})();
