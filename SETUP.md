# CAN42 Setup Guide (Part 1) - for beginners, Android only

You need: a free Supabase account, a free GitHub account, the Acode app, and a Cloudflare account (for hosting later).

## Step 1. Create the Supabase project
1. In your phone browser open supabase.com and sign up (tap "Start your project").
2. Tap **New project**. Name it `can42`. Choose a strong database password and SAVE it in a password manager. Pick the region closest to you.
3. Wait 1-2 minutes until the project is ready.

## Step 2. Create the database
1. In Supabase open **SQL Editor** (left menu; on phone tap the menu icon first).
2. Open `supabase/migrations/001_initial_schema.sql` in Acode, select all, copy.
3. In SQL Editor tap **New query**, paste, tap **Run**. You should see "Success".
4. Repeat for `002_security_policies.sql`, then `003_functions.sql`, then `004_initial_settings.sql`. Run each file ONCE and in this order.
   If you see an error, copy the exact message and send it to me with the word FIX.

## Step 3. Connect the website to Supabase
1. Supabase > **Project Settings > API**.
2. Copy **Project URL** and the **anon public** key.
3. In Acode open `assets/js/config.js`, replace `YOUR_SUPABASE_PROJECT_URL` and `YOUR_SUPABASE_ANON_KEY`. Save.
4. NEVER use or paste the `service_role` key in these files.

## Step 4. Configure sign-up emails
1. Supabase > **Authentication > Providers > Email**: keep "Confirm email" ON.
2. Supabase > **Authentication > URL Configuration**: set **Site URL** to your final website address (for example `https://can42.pages.dev`). Under **Redirect URLs** add `https://can42.pages.dev/**`.
   Until you know the address, use the one Cloudflare gives you in Step 6, then come back here.
3. Free-plan note: Supabase's built-in email sender allows only a few emails per hour, so test with 1-2 accounts. For real launch, connect your own email provider (needs a domain you own; Gmail addresses cannot be used as the sender). I will cover this in a later part.

## Step 5. Put the code on GitHub (from your phone)
1. In your phone browser open github.com > sign in > **New repository** > name `can42`. Choose **Private** for now.
2. On the repository page tap **Add file > Upload files** and upload the project files, keeping the folder names (`assets/css/...`, `supabase/migrations/...`). If folders are hard to upload, tap **Add file > Create new file**, type `assets/css/global.css` as the name (slashes create folders), paste the code, and tap **Commit**.
3. Do not upload any file containing real secrets. `.gitignore` already blocks `.env`.

## Step 6. Host free on Cloudflare Pages
1. Open dash.cloudflare.com, sign up, then **Workers & Pages > Create > Pages > Connect to Git**.
2. Choose your `can42` repo. Framework: **None**. Build command: leave empty. Output directory: `/`. Tap **Save and Deploy**.
3. You get an address like `https://can42.pages.dev`. Put it in `SITE_URL` in `config.js` and in Supabase Step 4.
Free limits: Cloudflare Pages free plan has monthly build limits and file-count limits, which are plenty for this site. Supabase free projects pause after about a week without activity and have a 500 MB database cap.

## Step 7. Create your first admin (never through the website)
1. Register normally on your site and verify your email.
2. Supabase > **Authentication > Users**: tap your user and copy the **User UID**.
3. SQL Editor > New query, paste this with YOUR UID, and Run:
```sql
insert into public.user_roles (user_id, role) values ('PASTE-YOUR-UID-HERE', 'super_admin');
```
Only you can do this because it needs your Supabase login.

## Step 8. Test Part 1 (Android)
- Open the site: header menu opens and closes, all sections show.
- Register with a real email, open the verification link, log in, log out.
- Forgot password: request a link, open it, set a new password, log in.
- Supabase > **Table Editor > profiles / wallets**: your row exists with a referral code.
- Referral test: register a second account at `register.html?ref=YOURCODE`. A row appears in `referrals`.
Pages like Earn, Wallet and Dashboard are added in Parts 2-6, so those menu links will show "not found" until then.
