// Core types for the Foodie agent pipeline. This module is dependency-free:
// everything here is shared by the orchestrator, tools, providers, and tests.

/** A tool invocation requested by the model. */
export interface ToolCall {
  id: string;
  name: string;
  input: unknown;
}

/** Provider-neutral description of a tool, mapped per-provider on the wire. */
export interface ToolSpec {
  name: string;
  description: string;
  /** JSON Schema for the input object. */
  inputSchema: Record<string, unknown>;
}

/** One model turn: text and/or requested tool calls. */
export interface ProviderTurn {
  text: string;
  toolCalls: ToolCall[];
}

/** Result of one executed tool call, fed back to the model verbatim. */
export interface ToolExecutionResult {
  toolCallId: string;
  ok: boolean;
  /** Structured payload on success, structured error on failure. */
  payload: unknown;
}

/** Provider-neutral conversation representation. */
export type ProviderMessage =
  | { role: "user"; text: string }
  | { role: "assistant"; text: string; toolCalls: ToolCall[] }
  | { role: "tool_results"; results: ToolExecutionResult[] };

export interface ProviderRequest {
  system: string;
  messages: ProviderMessage[];
  tools: ToolSpec[];
  maxTokens: number;
}

/**
 * The provider boundary. The orchestrator and tool layer know nothing about
 * Anthropic; swapping providers means writing one new implementation of this.
 */
export interface ModelProvider {
  generate(request: ProviderRequest): Promise<ProviderTurn>;
}

/** Structured tool/domain errors. Raw database errors never cross this line. */
export type ErrorCode =
  | "unauthenticated"
  | "no_household"
  | "unknown_tool"
  | "invalid_argument"
  | "not_authorized"
  | "internal";

export class FoodieError extends Error {
  constructor(readonly code: ErrorCode, message: string) {
    super(message);
  }
}

// ---------------------------------------------------------------------------
// Domain views exposed to tools (deliberately narrow — the model sees these
// shapes, never raw rows).
// ---------------------------------------------------------------------------

export type MemoryCategory = "household_fact" | "preference" | "historical_context";

export interface MemoryView {
  category: MemoryCategory;
  key: string;
  content: string;
}

export interface BasicHouseholdContext {
  householdName: string;
  timezone: string;
  memberNames: string[];
}

export interface GroceryItemView {
  name: string;
  quantity: number | null;
  unit: string | null;
  checked: boolean;
  notes: string | null;
}

export interface GroceryListView {
  listName: string;
  items: GroceryItemView[];
}

export interface HistoryMessage {
  role: "user" | "assistant";
  content: string;
}

export type ActionStatus = "executed" | "failed";

/** Intent-level audit entry (maps to the agent_actions table). */
export interface AgentActionRecord {
  householdId: string;
  requestedBy: string;
  conversationId: string;
  toolName: string;
  input: Record<string, unknown>;
  status: ActionStatus;
  resultSummary: string | null;
  error: string | null;
}

/**
 * Everything the pipeline may do to the database — the ONLY data access the
 * agent path has. Implemented over Supabase with the calling user's JWT
 * (RLS applies in full); mutations go through the foodie_* SQL functions
 * which record 'foodie' provenance. Faked in tests.
 */
export interface FoodieDb {
  /** The caller's household, or null (agent refuses to run without one). */
  getMembership(): Promise<{ householdId: string } | null>;

  getBasicContext(householdId: string): Promise<BasicHouseholdContext>;
  listMemories(householdId: string, categories: MemoryCategory[]): Promise<MemoryView[]>;
  saveMemory(
    householdId: string,
    category: MemoryCategory,
    key: string,
    content: string,
  ): Promise<MemoryView>;

  getGroceryList(householdId: string): Promise<GroceryListView>;
  addGroceryItem(
    householdId: string,
    item: { name: string; quantity?: number; unit?: string; notes?: string },
  ): Promise<GroceryItemView>;

  getOrCreateConversation(
    householdId: string,
    conversationId: string | null,
    contextTag: string,
  ): Promise<string>;
  getRecentMessages(conversationId: string, limit: number): Promise<HistoryMessage[]>;
  appendMessage(
    conversationId: string,
    householdId: string,
    role: "user" | "assistant",
    content: string,
    payload?: Record<string, unknown>,
  ): Promise<void>;

  /** Service-role write: clients cannot forge the audit trail. */
  recordAgentAction(action: AgentActionRecord): Promise<void>;
}

/** What the client receives. `actions` reflects ACTUAL tool executions —
 * the UI treats this, not the prose, as the record of what happened. */
export interface FoodieReply {
  conversationId: string;
  text: string;
  actions: Array<{ tool: string; status: ActionStatus; summary: string }>;
}
