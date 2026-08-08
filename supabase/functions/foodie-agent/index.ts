// foodie-agent Edge Function — composition root only. All behavior lives in
// _shared modules (tested with fakes); this file wires real dependencies:
// Supabase auth, the RLS-scoped database, and the Anthropic provider.
//
// Secrets (set with `supabase secrets set`, never in the client or repo):
//   ANTHROPIC_API_KEY  — required
//   FOODIE_MODEL       — optional, defaults below
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are provided
// by the Edge runtime.

import { createClient } from "npm:@supabase/supabase-js@2";
import { AnthropicProvider } from "../_shared/anthropic_provider.ts";
import { createHandler, type AuthedUser } from "../_shared/handler.ts";
import { SupabaseFoodieDb } from "../_shared/supabase_db.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const model = Deno.env.get("FOODIE_MODEL") ?? "claude-sonnet-5";

// This project is shared with Keep Track ("Katie"), which owns the default
// `public` schema. Both clients below default their PostgREST access to the
// `foodie` schema — this is not just documentation, it's a structural guard:
// an accidental .from('some_table') call resolves inside `foodie`, never
// `public`, without anyone having to remember to qualify it. Reaching a
// Keep Track table would require a conspicuous, deliberate .schema('public')
// override that does not exist anywhere in this codebase.
//
// service_role note: adminClient is used ONLY for the two Foodie-owned
// operations that need it — verifying a caller's JWT (auth.getUser, a
// GoTrue call unaffected by db.schema) and writing foodie.agent_actions
// (clients have no INSERT policy there). Every ordinary household read/write
// goes through userClient instead, under the caller's own JWT + RLS.
const adminClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
  db: { schema: "foodie" },
});

async function authenticate(req: Request): Promise<AuthedUser | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data.user) return null;
  return { userId: data.user.id, token };
}

function createDb(user: AuthedUser): SupabaseFoodieDb {
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${user.token}` } },
    auth: { persistSession: false },
    db: { schema: "foodie" },
  });
  return new SupabaseFoodieDb(userClient, adminClient, user.userId);
}

Deno.serve(createHandler({
  authenticate,
  createDb,
  provider: new AnthropicProvider(anthropicKey, model),
}));
