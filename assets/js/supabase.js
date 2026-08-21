const SUPABASE_URL = "https://xnotuefxovsctkgutpbn.supabase.co";

const SUPABASE_ANON_KEY = "sb_publishable_Y9v3V_3C_KspOttshO5BYQ_Eh11rnYl";

const supabaseClient = supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  }
);
console.log("Supabase connected", supabaseClient);
