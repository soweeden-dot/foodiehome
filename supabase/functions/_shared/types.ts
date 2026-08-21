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
  | "not_found"
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

export type SupplyLevel = "full" | "good" | "low" | "almost_empty" | "out";

export interface InventoryLocationView {
  id: string;
  name: string;
  kind: string;
}

export interface InventoryItemView {
  id: string;
  name: string;
  locationName: string | null;
  quantity: number | null;
  unit: string | null;
  level: SupplyLevel | null;
  expiresOn: string | null;
  openedOn: string | null;
  notes: string | null;
}

export interface InventoryView {
  locations: InventoryLocationView[];
  items: InventoryItemView[];
}

export interface NewInventoryItem {
  name: string;
  locationName?: string;
  quantity?: number;
  unit?: string;
  level?: SupplyLevel;
  expiresOn?: string;
  notes?: string;
}

/** Every field is "leave unchanged if omitted" — see foodie_update_inventory_item
 * in migration 14 and docs/FOODIE.md for why this call can't explicitly
 * clear a previously-set field back to null. */
export interface InventoryItemPatch {
  quantity?: number;
  unit?: string;
  level?: SupplyLevel;
  expiresOn?: string;
  openedOn?: string;
  notes?: string;
}

// ---------------------------------------------------------------------------
// Cleaning + Home Care (Migration 15). Next-due dates are COMPUTED at read
// time from recurrence.ts, never stored — see that module's header note.
// ---------------------------------------------------------------------------

export type CleaningOutcome = "completed" | "skipped";

export interface RecurrenceSummary {
  intervalUnit: "day" | "week" | "month" | "year";
  intervalCount: number;
  /** 0 = Sunday .. 6 = Saturday, or null for rules with no weekday anchor. */
  weekday: number | null;
}

export interface CleaningTaskView {
  id: string;
  name: string;
  area: string | null;
  recurrence: RecurrenceSummary | null;
  assignedUserName: string | null;
  suppliesNeeded: string[];
  /** Computed, ISO date — see computeCleaningDueDate. Null if the task has
   * no recurrence rule configured (nothing to compute a due date from). */
  nextDueOn: string | null;
  overdue: boolean;
  lastCompletedOn: string | null;
}

export interface CleaningStatusView {
  tasks: CleaningTaskView[];
}

export interface CleaningCompletionRecord {
  taskId: string;
  taskName: string;
  outcome: CleaningOutcome;
  notes: string | null;
}

export interface TrackedComponentView {
  id: string;
  systemName: string;
  componentName: string;
  kind: string;
  sparesCount: number;
  /** Computed, ISO date — null when the component has no replace interval. */
  nextDueOn: string | null;
  overdue: boolean;
  lastReplacedOn: string | null;
}

export interface FilterStatusView {
  components: TrackedComponentView[];
}

export type MaintenanceIssueStatus = "open" | "in_progress" | "resolved";

export interface MaintenanceIssueView {
  id: string;
  title: string;
  area: string | null;
  description: string | null;
  status: MaintenanceIssueStatus;
  reportedAt: string;
  resolvedAt: string | null;
  notes: string | null;
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

  getInventory(householdId: string): Promise<InventoryView>;
  addInventoryItem(householdId: string, item: NewInventoryItem): Promise<InventoryItemView>;
  updateInventoryItem(
    householdId: string,
    itemId: string,
    patch: InventoryItemPatch,
  ): Promise<InventoryItemView>;
  removeInventoryItem(householdId: string, itemId: string): Promise<InventoryItemView>;

  getCleaningStatus(householdId: string): Promise<CleaningStatusView>;
  completeCleaningTask(
    householdId: string,
    taskId: string,
    notes?: string,
  ): Promise<CleaningCompletionRecord>;
  skipCleaningTask(
    householdId: string,
    taskId: string,
    reason?: string,
  ): Promise<CleaningCompletionRecord>;

  getFilterStatus(householdId: string): Promise<FilterStatusView>;
  logFilterReplacement(
    householdId: string,
    componentId: string,
    notes?: string,
  ): Promise<TrackedComponentView>;

  getMaintenanceIssues(
    householdId: string,
    status?: MaintenanceIssueStatus,
  ): Promise<MaintenanceIssueView[]>;
  reportMaintenanceIssue(
    householdId: string,
    issue: { title: string; area?: string; description?: string },
  ): Promise<MaintenanceIssueView>;
  resolveMaintenanceIssue(
    householdId: string,
    issueId: string,
    notes?: string,
  ): Promise<MaintenanceIssueView>;

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
