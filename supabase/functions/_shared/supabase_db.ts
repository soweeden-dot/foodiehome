// Supabase implementation of FoodieDb.
//
// Two clients, two trust levels:
//  - userClient: anon key + the caller's JWT. Every domain read/write runs as
//    the user under RLS; mutations go through the foodie_* SQL functions,
//    which validate, enforce membership, and stamp 'foodie' provenance.
//  - adminClient: service role, used ONLY to write agent_actions (clients
//    have no insert policy there, so the audit trail cannot be forged).
//
// Postgres errors are mapped to structured FoodieError codes here; raw
// database errors never leave this module.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  FoodieError,
  type AgentActionRecord,
  type BasicHouseholdContext,
  type FoodieDb,
  type GroceryItemView,
  type GroceryListView,
  type HistoryMessage,
  type MemoryCategory,
  type MemoryView,
} from "./types.ts";

interface PgError {
  code?: string;
  message?: string;
}

function mapDbError(error: PgError, fallback: string): FoodieError {
  switch (error.code) {
    case "P0006":
      return new FoodieError("not_authorized", "not a member of that household");
    case "P0007":
      return new FoodieError("invalid_argument", error.message ?? "invalid argument");
    default:
      console.error("database error:", error.code, error.message);
      return new FoodieError("internal", fallback);
  }
}

export class SupabaseFoodieDb implements FoodieDb {
  constructor(
    private readonly userClient: SupabaseClient,
    private readonly adminClient: SupabaseClient,
    private readonly userId: string,
  ) {}

  async getMembership(): Promise<{ householdId: string } | null> {
    const { data, error } = await this.userClient
      .from("household_members")
      .select("household_id")
      .eq("user_id", this.userId)
      .limit(1);
    if (error) throw mapDbError(error, "could not resolve membership");
    if (!data || data.length === 0) return null;
    return { householdId: data[0].household_id as string };
  }

  async getBasicContext(householdId: string): Promise<BasicHouseholdContext> {
    const [householdResult, membersResult] = await Promise.all([
      this.userClient
        .from("households")
        .select("name, timezone")
        .eq("id", householdId)
        .single(),
      this.userClient
        .from("household_members")
        .select("profiles(display_name)")
        .eq("household_id", householdId),
    ]);
    if (householdResult.error) {
      throw mapDbError(householdResult.error, "could not load household");
    }
    if (membersResult.error) {
      throw mapDbError(membersResult.error, "could not load members");
    }
    return {
      householdName: householdResult.data.name as string,
      timezone: (householdResult.data.timezone as string) ?? "UTC",
      memberNames: (membersResult.data ?? [])
        .map((row) => (row.profiles as { display_name?: string } | null)?.display_name ?? "")
        .filter((name) => name.length > 0),
    };
  }

  async listMemories(
    householdId: string,
    categories: MemoryCategory[],
  ): Promise<MemoryView[]> {
    const { data, error } = await this.userClient
      .from("memories")
      .select("category, key, content")
      .eq("household_id", householdId)
      .in("category", categories)
      .eq("is_active", true)
      .is("deleted_at", null)
      .order("key");
    if (error) throw mapDbError(error, "could not load memories");
    return (data ?? []) as MemoryView[];
  }

  async saveMemory(
    householdId: string,
    category: MemoryCategory,
    key: string,
    content: string,
  ): Promise<MemoryView> {
    const { data, error } = await this.userClient.rpc("foodie_save_memory", {
      p_household: householdId,
      p_category: category,
      p_key: key,
      p_content: content,
    });
    if (error) throw mapDbError(error, "could not save the preference");
    return { category: data.category, key: data.key, content: data.content };
  }

  async getGroceryList(householdId: string): Promise<GroceryListView> {
    const { data: lists, error: listError } = await this.userClient
      .from("grocery_lists")
      .select("id, name")
      .eq("household_id", householdId)
      .is("archived_at", null)
      .is("deleted_at", null)
      .order("created_at")
      .limit(1);
    if (listError) throw mapDbError(listError, "could not load the grocery list");
    if (!lists || lists.length === 0) {
      return { listName: "Groceries", items: [] };
    }
    const { data: items, error: itemsError } = await this.userClient
      .from("grocery_items")
      .select("name, quantity, unit, checked_at, notes")
      .eq("grocery_list_id", lists[0].id)
      .is("deleted_at", null)
      .order("created_at");
    if (itemsError) throw mapDbError(itemsError, "could not load grocery items");
    return {
      listName: lists[0].name as string,
      items: (items ?? []).map((row): GroceryItemView => ({
        name: (row.name as string | null) ?? "(unnamed)",
        quantity: row.quantity === null ? null : Number(row.quantity),
        unit: row.unit as string | null,
        checked: row.checked_at !== null,
        notes: row.notes as string | null,
      })),
    };
  }

  async addGroceryItem(
    householdId: string,
    item: { name: string; quantity?: number; unit?: string; notes?: string },
  ): Promise<GroceryItemView> {
    const { data, error } = await this.userClient.rpc("foodie_add_grocery_item", {
      p_household: householdId,
      p_name: item.name,
      p_quantity: item.quantity ?? null,
      p_unit: item.unit ?? null,
      p_notes: item.notes ?? null,
    });
    if (error) throw mapDbError(error, "could not add the grocery item");
    return {
      name: data.name as string,
      quantity: data.quantity === null ? null : Number(data.quantity),
      unit: data.unit as string | null,
      checked: false,
      notes: data.notes as string | null,
    };
  }

  async getOrCreateConversation(
    householdId: string,
    conversationId: string | null,
    contextTag: string,
  ): Promise<string> {
    if (conversationId) {
      const { data, error } = await this.userClient
        .from("agent_conversations")
        .select("id")
        .eq("id", conversationId)
        .eq("household_id", householdId)
        .is("deleted_at", null)
        .limit(1);
      if (error) throw mapDbError(error, "could not load the conversation");
      if (data && data.length === 1) return conversationId;
      // Unknown/foreign conversation ids fall through to a fresh one rather
      // than leaking whether they exist.
    }
    const { data, error } = await this.userClient
      .from("agent_conversations")
      .insert({
        household_id: householdId,
        created_by: this.userId,
        context_tag: contextTag,
      })
      .select("id")
      .single();
    if (error) throw mapDbError(error, "could not create a conversation");
    return data.id as string;
  }

  async getRecentMessages(
    conversationId: string,
    limit: number,
  ): Promise<HistoryMessage[]> {
    const { data, error } = await this.userClient
      .from("agent_messages")
      .select("role, content, created_at")
      .eq("conversation_id", conversationId)
      .in("role", ["user", "assistant"])
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) throw mapDbError(error, "could not load conversation history");
    return (data ?? [])
      .reverse()
      .map((row) => ({
        role: row.role as "user" | "assistant",
        content: row.content as string,
      }));
  }

  async appendMessage(
    conversationId: string,
    householdId: string,
    role: "user" | "assistant",
    content: string,
    payload?: Record<string, unknown>,
  ): Promise<void> {
    const { error } = await this.userClient.from("agent_messages").insert({
      conversation_id: conversationId,
      household_id: householdId,
      role,
      content,
      payload: payload ?? null,
    });
    if (error) throw mapDbError(error, "could not store the message");
  }

  async recordAgentAction(action: AgentActionRecord): Promise<void> {
    const { error } = await this.adminClient.from("agent_actions").insert({
      household_id: action.householdId,
      conversation_id: action.conversationId,
      requested_by: action.requestedBy,
      tool_name: action.toolName,
      input: action.input,
      status: action.status,
      result_summary: action.resultSummary,
      error: action.error,
      source: "foodie",
      executed_at: new Date().toISOString(),
    });
    // Auditing must never silently fail: a mutation without an audit row is
    // worse than a failed request.
    if (error) throw mapDbError(error, "could not record the agent action");
  }
}
