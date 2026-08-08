// HTTP boundary for the foodie-agent Edge Function, dependency-injected so
// the request lifecycle (auth → membership → agent turn → response) is
// testable without Supabase or the network.

import { runFoodieTurn, type OrchestratorDeps } from "./orchestrator.ts";
import { FoodieError, type FoodieDb, type ModelProvider } from "./types.ts";

export interface AuthedUser {
  userId: string;
  /** The caller's JWT — used to build the RLS-scoped database client. */
  token: string;
}

export interface HandlerDeps {
  /** Resolves the caller from the request, or null if unauthenticated. */
  authenticate(req: Request): Promise<AuthedUser | null>;
  /** Builds the user-scoped data access for this request. */
  createDb(user: AuthedUser): FoodieDb;
  provider: ModelProvider;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function errorResponse(status: number, code: string, message: string): Response {
  return json(status, { error: { code, message } });
}

const MAX_MESSAGE_LENGTH = 4000;

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    if (req.method !== "POST") {
      return errorResponse(405, "method_not_allowed", "POST only");
    }

    const user = await deps.authenticate(req);
    if (!user) {
      return errorResponse(401, "unauthenticated", "sign in to talk to Foodie");
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json() as Record<string, unknown>;
    } catch {
      return errorResponse(400, "invalid_argument", "request body must be JSON");
    }

    const message = body["message"];
    if (typeof message !== "string" || message.trim().length === 0) {
      return errorResponse(400, "invalid_argument", "message is required");
    }
    if (message.length > MAX_MESSAGE_LENGTH) {
      return errorResponse(400, "invalid_argument", "message is too long");
    }
    const conversationId = body["conversation_id"];
    if (conversationId !== undefined && conversationId !== null && typeof conversationId !== "string") {
      return errorResponse(400, "invalid_argument", "conversation_id must be a string");
    }

    const orchestratorDeps: OrchestratorDeps = {
      db: deps.createDb(user),
      provider: deps.provider,
    };

    try {
      const reply = await runFoodieTurn(orchestratorDeps, {
        userId: user.userId,
        message: message.trim(),
        conversationId: (conversationId as string | undefined) ?? null,
      });
      return json(200, reply);
    } catch (error) {
      if (error instanceof FoodieError && error.code === "no_household") {
        return errorResponse(403, "no_household", "join a household before using Foodie");
      }
      console.error("foodie-agent turn failed:", error);
      return errorResponse(500, "internal", "Foodie hit an internal error");
    }
  };
}
