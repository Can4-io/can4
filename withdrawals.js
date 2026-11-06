// CAN42 | withdrawals.js - request form + history. The server (request_withdrawal) enforces every rule.
import { supabase } from './supabase.js';
import { $, escapeHtml, formatPoints, formatUsd, setMessage, setBusy, initProtectedPage, loadSettings,
  withdrawalRowHtml, emptyState, friendlyError } from './common.js';

let uid, settings, available = 0, minPoints = 0;
let requestKey = crypto.randomUUID();            // same key on retry = no duplicate request

async function loadHistory() {
  const { data, error } = await supabase.from('withdrawal_requests')
    .select('id,reference,points,amount_usd,method,status,created_at,admin_note,payment_reference')
    .eq('user_id', uid).order('created_at', { ascending: false }).limit(50);
  $('#wd-list').innerHTML = error ? emptyState('We could not load your requests.')
    : data.length ? data.map(withdrawalRowHtml).join('') : emptyState('No withdrawal requests yet.');
}
async function loadBalance() {
  const { data } = await supabase.from('wallets').select('available_points').eq('user_id', uid).maybeSingle();
  available = Number(data?.available_points || 0);
  $('#wd-balance').textContent = `Available: ${formatPoints(available)} points`;
  updateHelp();
}
function updateHelp() {
  const pts = Number($('#points').value);
  const usd = pts > 0 ? ` = about ${formatUsd(pts, settings.points_per_usd)}` : '';
  $('#points-help').textContent = `Minimum ${formatPoints(minPoints)} points ($${settings.min_withdrawal_usd})${usd}`;
}
function updateMethod() {
  const bank = $('#method').value === 'bank_transfer';
  $('#bank-field').hidden = !bank;
  $('#account-label').textContent = bank ? 'Bank account number or IBAN' : 'Mobile account number';
}

(async function init() {
  const session = await initProtectedPage('withdrawals');
  if (!session) return;
  uid = session.user.id;
  settings = await loadSettings();
  minPoints = Math.ceil(settings.min_withdrawal_usd * settings.points_per_usd);

  const fields = $('#wd-fields');
  if (!settings.payouts_enabled) {
    fields.disabled = true;
    $('#notices').innerHTML = '<p class="notice-box notice-info">Withdrawals are not open yet. This form unlocks only after campaigns are funded and legal, tax, age and payment checks are complete.</p>';
  }
  updateMethod();
  await Promise.all([loadBalance(), loadHistory()]);

  $('#method').addEventListener('change', updateMethod);
  $('#points').addEventListener('input', updateHelp);
  $('#use-all').addEventListener('click', () => { $('#points').value = String(available); updateHelp(); });

  const form = $('#wd-form');
  form.addEventListener('submit', async e => {
    e.preventDefault();
    setMessage(form, '');
    if (!settings.payouts_enabled) return setMessage(form, 'Withdrawals are not open yet.');
    const method = $('#method').value;
    const pts = Number($('#points').value);
    const holder = $('#holder').value.trim().replace(/\s+/g, ' ');
    const account = $('#account').value.trim();
    const bank = $('#bank').value.trim();
    if (!Number.isInteger(pts) || pts <= 0) return setMessage(form, 'Enter a whole number of points.');
    if (pts < minPoints) return setMessage(form, `The minimum is ${formatPoints(minPoints)} points.`);
    if (pts > available) return setMessage(form, 'You do not have enough available points.');
    if (holder.length < 2) return setMessage(form, 'Enter the account holder name.');
    if (!/^[A-Za-z0-9 -]{6,34}$/.test(account)) return setMessage(form, 'Enter a valid account or phone number (letters, numbers, spaces and dashes only).');
    if (method === 'bank_transfer' && bank.length < 2) return setMessage(form, 'Enter the bank name.');
    if (!$('#confirm').checked) return setMessage(form, 'Please confirm that your details are correct.');

    const btn = $('#wd-submit');
    setBusy(btn, true, 'Submitting...');
    const { error } = await supabase.rpc('request_withdrawal', {
      p_points: pts, p_method: method, p_account_holder: holder, p_account_number: account,
      p_bank_name: method === 'bank_transfer' ? bank : null, p_idempotency_key: requestKey
    });
    setBusy(btn, false);
    if (error) { console.error(error); return setMessage(form, friendlyError(error)); }
    requestKey = crypto.randomUUID();           // new key only after success
    form.reset(); updateMethod();
    setMessage(form, 'Request submitted. We will review it and notify you.', 'ok');
    await Promise.all([loadBalance(), loadHistory()]);
  });
})();
