// CAN42 | supabase.js - creates the single Supabase client used by every page.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { CONFIG } from './config.js';

export const isConfigured =
  /^https:\/\/.+\.supabase\.co/.test(CONFIG.SUPABASE_URL) && !CONFIG.SUPABASE_ANON_KEY.startsWith('YOUR_');

export const supabase = createClient(
  isConfigured ? CONFIG.SUPABASE_URL : 'https://placeholder.supabase.co',
  isConfigured ? CONFIG.SUPABASE_ANON_KEY : 'placeholder-key',
  { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } }
);
