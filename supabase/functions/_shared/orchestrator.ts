// The Foodie agent loop. Pure with respect to I/O: everything external comes
// through FoodieDb and ModelProvider, so the whole pipeline is testable with
// fakes. The loop is where the safety property lives: tool results fed to the
// model are ALWAYS the outcome of real, validated execution — the model
// cannot invent a successful mutation, and the client's `actions` list is
// built from actual executions, never from prose.

import { buildSystemPrompt } from "./context.ts";
import { toolRegistry, type ToolDefinition } from "./tools.ts";
import {
  FoodieError,
  type FoodieDb,
  type FoodieReply,
  type ModelProvider,
  type ProviderMessage,
  type ToolExecutionResult,
} from "./types.ts";

export interface OrchestratorDeps {
  db: FoodieDb;
  provider: ModelProvider;
  registry?: ReadonlyMap<string, ToolDefinition>;
  /** Injectable clock for tests. */
  today?: () => string;
}

export interface TurnInput {
  userId: string;
  message: string;
  conversationId: string | null;
  contextTag?: string;
}

const MAX_TOOL_ITERATIONS = 5;
const HISTORY_LIMIT = 20;
const MAX_TOKENS = 1024;

export async function runFoodieTurn(
  deps: OrchestratorDeps,
  input: TurnInput,
): Promise<FoodieReply> {
  const { db, provider } = deps;
  const registry = deps.registry ?? toolRegistry;
  const todayIso = (deps.today ?? (() => new Date().toISOString().slice(0, 10)))();

  const membership = await db.getMembership();
  if (!membership) {
    throw new FoodieError("no_household", "user does not belong to a household");
  }
  const { householdId } = membership;

  const conversationId = await db.getOrCreateConversation(
    householdId,
    input.conversationId,
    input.contextTag ?? "chat",
  );

  // Conversation slice + durable preferences — assembled fresh every turn;
  // history is storage, not memory (see docs/FOODIE.md).
  const [household, preferences, history] = await Promise.all([
    db.getBasicContext(householdId),
    db.listMemories(householdId, ["preference"]),
    db.getRecentMessages(conversationId, HISTORY_LIMIT),
  ]);

  await db.appendMessage(conversationId, householdId, "user", input.message);

  const system = buildSystemPrompt({ household, preferences, todayIso });
  const specs = [...registry.values()].map((tool) => tool.spec);

  const messages: ProviderMessage[] = [
    ...history.map((m): ProviderMessage =>
      m.role === "user"
        ? { role: "user", text: m.content }
        : { role: "assistant", text: m.content, toolCalls: [] }
    ),
    { role: "user", text: input.message },
  ];

  const executedActions: FoodieReply["actions"] = [];
  let finalText = "";

  for (let iteration = 0; iteration < MAX_TOOL_ITERATIONS; iteration++) {
    const turn = await provider.generate({
      system,
      messages,
      tools: specs,
      maxTokens: MAX_TOKENS,
    });

    if (turn.toolCalls.length === 0) {
      finalText = turn.text;
      break;
    }

    messages.push({ role: "assistant", text: turn.text, toolCalls: turn.toolCalls });

    const results: ToolExecutionResult[] = [];
    for (const call of turn.toolCalls) {
      const result = await executeToolCall(deps, registry, {
        householdId,
        userId: input.userId,
        conversationId,
      }, call.name, call.input);
      results.push({ toolCallId: call.id, ok: result.ok, payload: result.payload });
      if (result.audit) executedActions.push(result.audit);
    }
    messages.push({ role: "tool_results", results });

    // Cap reached with tools still being requested: stop honestly.
    if (iteration === MAX_TOOL_ITERATIONS - 1) {
      finalText =
        "I stopped before finishing — I hit my per-message action limit. " +
        "The actions listed below did complete.";
    }
  }

  if (finalText.trim().length === 0) {
    finalText = "(Foodie had nothing to say.)";
  }

  await db.appendMessage(conversationId, householdId, "assistant", finalText, {
    actions: executedActions,
  });

  return { conversationId, text: finalText, actions: executedActions };
}

interface ExecutionScope {
  householdId: string;
  userId: string;
  conversationId: string;
}

interface CallResult {
  ok: boolean;
  payload: unknown;
  audit?: FoodieReply["actions"][number];
}

async function executeToolCall(
  deps: OrchestratorDeps,
  registry: ReadonlyMap<string, ToolDefinition>,
  scope: ExecutionScope,
  name: string,
  rawInput: unknown,
): Promise<CallResult> {
  const record = async (
    toolName: string,
    input: Record<string, unknown>,
    status: "executed" | "failed",
    summary: string | null,
    error: string | null,
  ) => {
    await deps.db.recordAgentAction({
      householdId: scope.householdId,
      requestedBy: scope.userId,
      conversationId: scope.conversationId,
      toolName,
      input,
      status,
      resultSummary: summary,
      error,
    });
  };

  const tool = registry.get(name);
  if (!tool) {
    const message = `unknown tool "${name.slice(0, 80)}"`;
    await record(name.slice(0, 80), {}, "failed", null, message);
    return { ok: false, payload: { error: { code: "unknown_tool", message } } };
  }

  const validation = tool.validate(rawInput);
  if (!validation.ok) {
    await record(name, {}, "failed", null, `invalid arguments: ${validation.error}`);
    return {
      ok: false,
      payload: { error: { code: "invalid_argument", message: validation.error } },
      audit: { tool: name, status: "failed", summary: `Rejected: ${validation.error}` },
    };
  }

  try {
    const outcome = await tool.execute(
      { db: deps.db, householdId: scope.householdId, userId: scope.userId },
      validation.value,
    );
    // Read-only tools are audited but not surfaced as user-visible actions.
    await record(name, validation.value, "executed", outcome.summary, null);
    return {
      ok: true,
      payload: { ok: true, result: outcome.data },
      audit: tool.mutating
        ? { tool: name, status: "executed", summary: outcome.summary }
        : undefined,
    };
  } catch (error) {
    const safe = error instanceof FoodieError
      ? { code: error.code, message: error.message }
      : { code: "internal" as const, message: "the tool failed unexpectedly" };
    await record(name, validation.value, "failed", null, safe.message);
    return {
      ok: false,
      payload: { error: safe },
      audit: { tool: name, status: "failed", summary: `Failed: ${safe.message}` },
    };
  }
}
