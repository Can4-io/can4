# CAN42 - Parts 1 and 2 (Foundation, Dashboard and Wallet)

Watch. Earn. Connect. A static website (HTML/CSS/JavaScript) with a Supabase backend.
Part 1 = landing and sign-in. Part 2 = dashboard, wallet, transactions, withdrawals form (locked), profile, notifications. Later parts add earning, referrals, support, the admin panel and policy pages.

## Where each file belongs (keep these exact folder names)

CAN42/
- index.html ............... Landing page (site root)
- login.html ............... Log in page (site root)
- register.html ............ Create account page (site root)
- forgot-password.html ..... Request a password reset link (site root)
- reset-password.html ...... Page the reset email opens to set a new password (site root)
- README.md ................ This file
- SETUP.md ................. Step-by-step beginner setup (start here)
- .gitignore ............... Stops secret files (.env) being uploaded to GitHub
- .env.example ............. Placeholder secret names for later Edge Functions (no real secrets)

assets/css/
- global.css ............... Colors, buttons, header, footer, forms (used by every page)
- landing.css .............. Landing page sections (index.html only)
- auth.css ................. Login / register / reset layout
- responsive.css ........... Phone and tablet adjustments (loaded last on every page)

assets/js/
- config.js ................ YOUR Supabase URL and anon key go here
- supabase.js .............. Creates the Supabase connection
- common.js ................ Shared header, footer, icons, helpers, log out
- auth.js .................. Register, login, forgot and reset password logic

assets/images/
- logo.svg ................. CAN42 logo
- favicon.svg .............. Browser tab icon

supabase/migrations/ (run in Supabase SQL Editor, in this order, once each)
- 001_initial_schema.sql ... All 15 tables
- 002_security_policies.sql  Row Level Security and permissions
- 003_functions.sql ........ Points ledger, withdrawal and admin functions, new-user trigger
- 004_initial_settings.sql . Starting settings (rewards and payouts OFF)

## Quick start
1. Unzip, keeping the folder structure.
2. Follow SETUP.md from Step 1.
3. Never put the Supabase service_role key in any file.

Menu links to pages not in Part 1 (Earn, Wallet, FAQ, etc.) will show "not found" until later parts.

## Added in Part 2
CAN42/
- dashboard.html, wallet.html, transactions.html, withdrawals.html, profile.html, notifications.html ... signed-in pages (site root)
- coming-soon.html ... shown for pages not built yet
- assets/css/dashboard.css ... layout for all signed-in pages
- assets/css/wallet.css ... wallet balance card and progress bar
- assets/js/dashboard.js, wallet.js, transactions.js, withdrawals.js, profile.js, notifications.js ... one script per page
Changed: assets/js/config.js, assets/js/common.js, assets/css/responsive.css, SETUP.md, README.md
No new SQL migrations are needed for Part 2.
