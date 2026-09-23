'use strict';

// Requires the Supabase CDN script (loaded before this file — see
// signup.html) which exposes a global `supabase` object with
// `.createClient()`. The client instance below is named
// `supabaseClient`, not `supabase` — naming it the same as the global
// would be a self-reference: `const supabase = supabase.createClient(...)`
// throws ReferenceError, since `const` bindings aren't initialized
// until the whole statement completes, so the right-hand side can't
// see the CDN's `supabase` global through its own not-yet-assigned name.
//
// SUPABASE_URL / SUPABASE_ANON_KEY are placeholders — there is no real
// Supabase project configured for this prototype. Every exported
// function below will reject/error until these are replaced with real
// project credentials.
const SUPABASE_URL = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';

const supabaseClient = window.supabase
  ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;

async function signUp(email, password, displayName) {
  if (!supabaseClient) throw new Error('Supabase client not initialized — check SUPABASE_URL/SUPABASE_ANON_KEY.');
  const { data, error } = await supabaseClient.auth.signUp({
    email,
    password,
    options: { data: { display_name: displayName } },
  });
  if (error) throw error;
  return data;
}

async function signOut() {
  if (!supabaseClient) throw new Error('Supabase client not initialized — check SUPABASE_URL/SUPABASE_ANON_KEY.');
  const { error } = await supabaseClient.auth.signOut();
  if (error) throw error;
}

async function getSession() {
  if (!supabaseClient) return null;
  const { data } = await supabaseClient.auth.getSession();
  return data.session;
}

function onAuthChange(callback) {
  if (!supabaseClient) return { data: { subscription: { unsubscribe() {} } } };
  return supabaseClient.auth.onAuthStateChange(callback);
}
