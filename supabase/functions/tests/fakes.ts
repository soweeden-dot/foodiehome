// In-memory fakes for the agent pipeline tests. FakeDb mimics the RLS
// behavior that matters (membership gating); FakeProvider plays scripted
// model turns so tests control exactly what the "model" tries to do.

import type {
  AgentActionRecord,
  BasicHouseholdContext,
  FoodieDb,
  GroceryItemView,
  GroceryListView,
  HistoryMessage,
  MemoryCategory,
  MemoryView,
  ModelProvider,
  ProviderRequest,
  ProviderTurn,
} from "../_shared/types.ts";
import { FoodieError } from "../_shared/types.ts";

export class FakeDb implements FoodieDb {
  membership: { householdId: string } | null = { householdId: "hh-1" };
  context: BasicHouseholdContext = {
    householdName: "Test Home",
    timezone: "UTC",
    memberNames: ["Sam", "Alex"],
  };
  memories: Array<MemoryView & { active: boolean }> = [];
  groceryItems: GroceryItemView[] = [];
  conversations = new Map<string, { householdId: string; messages: Array<
    { role: string; content: string; payload?: Record<string, unknown> }
  > }>();
  actions: AgentActionRecord[] = [];
  failNextGroceryAdd: FoodieError | null = null;
  private conversationCounter = 0;

  getMembership(): Promise<{ householdId: string } | null> {
    return Promise.resolve(this.membership);
  }

  getBasicContext(_householdId: string): Promise<BasicHouseholdContext> {
    return Promise.resolve(this.context);
  }

  listMemories(
    _householdId: string,
    categories: MemoryCategory[],
  ): Promise<MemoryView[]> {
    return Promise.resolve(
      this.memories
        .filter((m) => m.active && categories.includes(m.category))
        .map(({ category, key, content }) => ({ category, key, content })),
    );
  }

  saveMemory(
    _householdId: string,
    category: MemoryCategory,
    key: string,
    content: string,
  ): Promise<MemoryView> {
    const existing = this.memories.find((m) => m.category === category && m.key === key);
    if (existing) {
      existing.content = content;
      existing.active = true;
    } else {
      this.memories.push({ category, key, content, active: true });
    }
    return Promise.resolve({ category, key, content });
  }

  getGroceryList(_householdId: string): Promise<GroceryListView> {
    return Promise.resolve({ listName: "Groceries", items: [...this.groceryItems] });
  }

  addGroceryItem(
    _householdId: string,
    item: { name: string; quantity?: number; unit?: string; notes?: string },
  ): Promise<GroceryItemView> {
    if (this.failNextGroceryAdd) {
      const error = this.failNextGroceryAdd;
      this.failNextGroceryAdd = null;
      return Promise.reject(error);
    }
    const view: GroceryItemView = {
      name: item.name,
      quantity: item.quantity ?? null,
      unit: item.unit ?? null,
      checked: false,
      notes: item.notes ?? null,
    };
    this.groceryItems.push(view);
    return Promise.resolve(view);
  }

  getOrCreateConversation(
    householdId: string,
    conversationId: string | null,
    _contextTag: string,
  ): Promise<string> {
    if (conversationId && this.conversations.has(conversationId)) {
      return Promise.resolve(conversationId);
    }
    const id = `conv-${++this.conversationCounter}`;
    this.conversations.set(id, { householdId, messages: [] });
    return Promise.resolve(id);
  }

  getRecentMessages(conversationId: string, limit: number): Promise<HistoryMessage[]> {
    const conversation = this.conversations.get(conversationId);
    const messages = (conversation?.messages ?? [])
      .filter((m) => m.role === "user" || m.role === "assistant")
      .slice(-limit)
      .map((m) => ({ role: m.role as "user" | "assistant", content: m.content }));
    return Promise.resolve(messages);
  }

  appendMessage(
    conversationId: string,
    _householdId: string,
    role: "user" | "assistant",
    content: string,
    payload?: Record<string, unknown>,
  ): Promise<void> {
    this.conversations.get(conversationId)?.messages.push({ role, content, payload });
    return Promise.resolve();
  }

  recordAgentAction(action: AgentActionRecord): Promise<void> {
    this.actions.push(action);
    return Promise.resolve();
  }
}

export class FakeProvider implements ModelProvider {
  requests: ProviderRequest[] = [];
  private turns: ProviderTurn[];

  constructor(turns: ProviderTurn[]) {
    this.turns = [...turns];
  }

  generate(request: ProviderRequest): Promise<ProviderTurn> {
    this.requests.push(request);
    const next = this.turns.shift();
    if (!next) throw new Error("FakeProvider ran out of scripted turns");
    return Promise.resolve(next);
  }
}
