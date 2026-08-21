// In-memory fakes for the agent pipeline tests. FakeDb mimics the RLS
// behavior that matters (membership gating); FakeProvider plays scripted
// model turns so tests control exactly what the "model" tries to do.

import type {
  AgentActionRecord,
  BasicHouseholdContext,
  CleaningCompletionRecord,
  CleaningStatusView,
  CleaningTaskView,
  FilterStatusView,
  FoodieDb,
  GroceryItemView,
  GroceryListView,
  HistoryMessage,
  InventoryItemPatch,
  InventoryItemView,
  InventoryLocationView,
  InventoryView,
  MaintenanceIssueStatus,
  MaintenanceIssueView,
  MemoryCategory,
  MemoryView,
  ModelProvider,
  NewInventoryItem,
  ProviderRequest,
  ProviderTurn,
  RecurrenceSummary,
  TrackedComponentView,
} from "../_shared/types.ts";
import { FoodieError } from "../_shared/types.ts";
import { computeCleaningDueDate, computeComponentDueDate, isOverdue } from "../_shared/recurrence.ts";

interface FakeCleaningTask {
  id: string;
  name: string;
  area: string | null;
  rule: RecurrenceSummary | null;
  assignedUserName: string | null;
  suppliesNeeded: string[];
  lastCompletedOn: string | null;
  deleted: boolean;
}

interface FakeComponent {
  id: string;
  systemName: string;
  componentName: string;
  kind: string;
  installedOn: string | null;
  replaceIntervalDays: number | null;
  sparesCount: number;
  lastReplacedOn: string | null;
  deleted: boolean;
}

interface FakeMaintenanceIssue {
  id: string;
  title: string;
  area: string | null;
  description: string | null;
  status: MaintenanceIssueStatus;
  reportedAt: string;
  resolvedAt: string | null;
  notes: string | null;
  deleted: boolean;
}

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
  failNextInventoryAdd: FoodieError | null = null;
  inventoryLocations: InventoryLocationView[] = [];
  // deleted items stay in the array with deleted=true, mirroring the real
  // soft-delete schema, and are filtered out of getInventory/lookups.
  inventoryItems: Array<InventoryItemView & { deleted: boolean }> = [];
  cleaningTasks: FakeCleaningTask[] = [];
  trackedComponents: FakeComponent[] = [];
  maintenanceIssues: FakeMaintenanceIssue[] = [];
  private conversationCounter = 0;
  private inventoryCounter = 0;
  private maintenanceCounter = 0;

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

  getInventory(_householdId: string): Promise<InventoryView> {
    return Promise.resolve({
      locations: [...this.inventoryLocations],
      items: this.inventoryItems.filter((i) => !i.deleted).map(({ deleted: _d, ...view }) => view),
    });
  }

  private resolveOrCreateLocation(name: string | undefined): string | null {
    if (!name || name.trim().length === 0) return null;
    const trimmed = name.trim();
    const existing = this.inventoryLocations.find(
      (l) => l.name.toLowerCase() === trimmed.toLowerCase(),
    );
    if (existing) return existing.name;
    this.inventoryLocations.push({ id: `loc-${this.inventoryLocations.length + 1}`, name: trimmed, kind: "other" });
    return trimmed;
  }

  addInventoryItem(
    _householdId: string,
    item: NewInventoryItem,
  ): Promise<InventoryItemView> {
    if (this.failNextInventoryAdd) {
      const error = this.failNextInventoryAdd;
      this.failNextInventoryAdd = null;
      return Promise.reject(error);
    }
    const locationName = this.resolveOrCreateLocation(item.locationName);
    const view: InventoryItemView & { deleted: boolean } = {
      id: `inv-${++this.inventoryCounter}`,
      name: item.name,
      locationName,
      quantity: item.quantity ?? null,
      unit: item.unit ?? null,
      level: item.level ?? null,
      expiresOn: item.expiresOn ?? null,
      openedOn: null,
      notes: item.notes ?? null,
      deleted: false,
    };
    this.inventoryItems.push(view);
    const { deleted: _d, ...result } = view;
    return Promise.resolve(result);
  }

  updateInventoryItem(
    _householdId: string,
    itemId: string,
    patch: InventoryItemPatch,
  ): Promise<InventoryItemView> {
    const item = this.inventoryItems.find((i) => i.id === itemId && !i.deleted);
    if (!item) {
      return Promise.reject(new FoodieError("not_found", "inventory item not found"));
    }
    if (patch.quantity !== undefined) item.quantity = patch.quantity;
    if (patch.unit !== undefined) item.unit = patch.unit;
    if (patch.level !== undefined) item.level = patch.level;
    if (patch.expiresOn !== undefined) item.expiresOn = patch.expiresOn;
    if (patch.openedOn !== undefined) item.openedOn = patch.openedOn;
    if (patch.notes !== undefined) item.notes = patch.notes;
    const { deleted: _d, ...result } = item;
    return Promise.resolve(result);
  }

  removeInventoryItem(_householdId: string, itemId: string): Promise<InventoryItemView> {
    const item = this.inventoryItems.find((i) => i.id === itemId && !i.deleted);
    if (!item) {
      return Promise.reject(new FoodieError("not_found", "inventory item not found"));
    }
    item.deleted = true;
    const { deleted: _d, ...result } = item;
    return Promise.resolve(result);
  }

  getCleaningStatus(_householdId: string): Promise<CleaningStatusView> {
    const today = new Date();
    const tasks: CleaningTaskView[] = this.cleaningTasks
      .filter((t) => !t.deleted)
      .map((t) => {
        let nextDueOn: string | null = null;
        if (t.rule) {
          const due = computeCleaningDueDate({
            rule: { ...t.rule, anchorDate: null },
            lastCompletedOn: t.lastCompletedOn,
            today,
          });
          nextDueOn = due.toISOString().slice(0, 10);
        }
        return {
          id: t.id,
          name: t.name,
          area: t.area,
          recurrence: t.rule,
          assignedUserName: t.assignedUserName,
          suppliesNeeded: t.suppliesNeeded,
          nextDueOn,
          overdue: nextDueOn !== null && isOverdue(new Date(nextDueOn), today),
          lastCompletedOn: t.lastCompletedOn,
        };
      });
    return Promise.resolve({ tasks });
  }

  private findCleaningTask(taskId: string): FakeCleaningTask {
    const task = this.cleaningTasks.find((t) => t.id === taskId && !t.deleted);
    if (!task) throw new FoodieError("not_found", "cleaning task not found");
    return task;
  }

  completeCleaningTask(
    _householdId: string,
    taskId: string,
    notes?: string,
  ): Promise<CleaningCompletionRecord> {
    let task: FakeCleaningTask;
    try {
      task = this.findCleaningTask(taskId);
    } catch (error) {
      return Promise.reject(error);
    }
    task.lastCompletedOn = new Date().toISOString().slice(0, 10);
    return Promise.resolve({
      taskId: task.id,
      taskName: task.name,
      outcome: "completed",
      notes: notes ?? null,
    });
  }

  skipCleaningTask(
    _householdId: string,
    taskId: string,
    reason?: string,
  ): Promise<CleaningCompletionRecord> {
    let task: FakeCleaningTask;
    try {
      task = this.findCleaningTask(taskId);
    } catch (error) {
      return Promise.reject(error);
    }
    return Promise.resolve({
      taskId: task.id,
      taskName: task.name,
      outcome: "skipped",
      notes: reason ?? null,
    });
  }

  getFilterStatus(_householdId: string): Promise<FilterStatusView> {
    const today = new Date();
    const components: TrackedComponentView[] = this.trackedComponents
      .filter((c) => !c.deleted)
      .map((c) => {
        const due = computeComponentDueDate({
          replaceIntervalDays: c.replaceIntervalDays,
          lastReplacedOn: c.lastReplacedOn,
          installedOn: c.installedOn,
        });
        const nextDueOn = due ? due.toISOString().slice(0, 10) : null;
        return {
          id: c.id,
          systemName: c.systemName,
          componentName: c.componentName,
          kind: c.kind,
          sparesCount: c.sparesCount,
          nextDueOn,
          overdue: nextDueOn !== null && isOverdue(new Date(nextDueOn), today),
          lastReplacedOn: c.lastReplacedOn,
        };
      });
    return Promise.resolve({ components });
  }

  logFilterReplacement(
    _householdId: string,
    componentId: string,
    _notes?: string,
  ): Promise<TrackedComponentView> {
    const component = this.trackedComponents.find((c) => c.id === componentId && !c.deleted);
    if (!component) {
      return Promise.reject(new FoodieError("not_found", "tracked component not found"));
    }
    component.lastReplacedOn = new Date().toISOString().slice(0, 10);
    component.sparesCount = Math.max(component.sparesCount - 1, 0);
    const due = computeComponentDueDate({
      replaceIntervalDays: component.replaceIntervalDays,
      lastReplacedOn: component.lastReplacedOn,
      installedOn: component.installedOn,
    });
    return Promise.resolve({
      id: component.id,
      systemName: component.systemName,
      componentName: component.componentName,
      kind: component.kind,
      sparesCount: component.sparesCount,
      nextDueOn: due ? due.toISOString().slice(0, 10) : null,
      overdue: false,
      lastReplacedOn: component.lastReplacedOn,
    });
  }

  getMaintenanceIssues(
    _householdId: string,
    status?: MaintenanceIssueStatus,
  ): Promise<MaintenanceIssueView[]> {
    const issues = this.maintenanceIssues
      .filter((i) => !i.deleted && (status === undefined || i.status === status))
      .map(({ deleted: _d, ...view }) => view);
    return Promise.resolve(issues);
  }

  reportMaintenanceIssue(
    _householdId: string,
    issue: { title: string; area?: string; description?: string },
  ): Promise<MaintenanceIssueView> {
    const view: FakeMaintenanceIssue = {
      id: `issue-${++this.maintenanceCounter}`,
      title: issue.title,
      area: issue.area ?? null,
      description: issue.description ?? null,
      status: "open",
      reportedAt: new Date().toISOString(),
      resolvedAt: null,
      notes: null,
      deleted: false,
    };
    this.maintenanceIssues.push(view);
    const { deleted: _d, ...result } = view;
    return Promise.resolve(result);
  }

  resolveMaintenanceIssue(
    _householdId: string,
    issueId: string,
    notes?: string,
  ): Promise<MaintenanceIssueView> {
    const issue = this.maintenanceIssues.find((i) => i.id === issueId && !i.deleted);
    if (!issue) {
      return Promise.reject(new FoodieError("not_found", "maintenance issue not found"));
    }
    issue.status = "resolved";
    issue.resolvedAt = new Date().toISOString();
    if (notes !== undefined) issue.notes = notes;
    const { deleted: _d, ...result } = issue;
    return Promise.resolve(result);
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
