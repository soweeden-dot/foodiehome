// Supabase implementation of FoodieDb.
//
// Two clients, two trust levels:
//  - userClient: anon key + the caller's JWT. Every domain read/write runs as
//    the user under RLS; mutations go through the foodie_* SQL functions,
//    which validate, enforce membership, and stamp 'foodie' provenance.
//  - adminClient: service role, used ONLY to write agent_actions (clients
//    have no insert policy there, so the audit trail cannot be forged).
//
// SCHEMA: this project is shared with Keep Track ("Katie"), which owns the
// default `public` schema; all Foodie tables/RPCs live in `foodie`. Both
// clients are constructed with `db: { schema: "foodie" }` in
// foodie-agent/index.ts, so every .from()/.rpc() call below is already
// scoped there — no per-call schema qualification needed here, and no code
// in this file can reach a `public` (Keep Track) table without a deliberate,
// conspicuous .schema('public') override, which does not exist anywhere in
// this codebase.
//
// Postgres errors are mapped to structured FoodieError codes here; raw
// database errors never leave this module.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  FoodieError,
  type AgentActionRecord,
  type BasicHouseholdContext,
  type CleaningCompletionRecord,
  type CleaningStatusView,
  type CleaningTaskView,
  type FermentationLogType,
  type FermentationLogView,
  type FermentationProjectDetail,
  type FermentationProjectView,
  type FermentationStatus,
  type FilterStatusView,
  type FoodieDb,
  type GroceryItemView,
  type GroceryListView,
  type HistoryMessage,
  type InventoryItemPatch,
  type InventoryItemView,
  type InventoryView,
  type InventoryLocationView,
  type MaintenanceIssueStatus,
  type MaintenanceIssueView,
  type MemoryCategory,
  type MemoryView,
  type NewInventoryItem,
  type TrackedComponentView,
} from "./types.ts";
import { computeCleaningDueDate, computeComponentDueDate, isOverdue } from "./recurrence.ts";

// supabase-js's SupabaseClient type is generic over the active schema
// (5th type param). Both clients passed in here are constructed with
// `db: { schema: "foodie" }` in foodie-agent/index.ts — that's the whole
// point (see the header comment) — so the bare `SupabaseClient` type
// (implicitly `"public"`) would reject them at compile time. Widened here
// rather than threaded through as a generic, since this module doesn't
// otherwise care about the schema type parameter.
// deno-lint-ignore no-explicit-any
type AnySupabaseClient = SupabaseClient<any, any, any, any, any>;

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
    case "P0008":
      return new FoodieError("not_found", error.message ?? "not found");
    default:
      console.error("database error:", error.code, error.message);
      return new FoodieError("internal", fallback);
  }
}

export class SupabaseFoodieDb implements FoodieDb {
  constructor(
    private readonly userClient: AnySupabaseClient,
    private readonly adminClient: AnySupabaseClient,
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

  async getInventory(householdId: string): Promise<InventoryView> {
    const [locationsResult, itemsResult] = await Promise.all([
      this.userClient
        .from("inventory_locations")
        .select("id, name, kind")
        .eq("household_id", householdId)
        .is("deleted_at", null)
        .order("position"),
      this.userClient
        .from("inventory_items")
        .select("id, name, quantity, unit, level, expires_on, opened_on, notes, inventory_locations(name)")
        .eq("household_id", householdId)
        .is("deleted_at", null)
        .order("created_at"),
    ]);
    if (locationsResult.error) {
      throw mapDbError(locationsResult.error, "could not load inventory locations");
    }
    if (itemsResult.error) {
      throw mapDbError(itemsResult.error, "could not load inventory items");
    }
    return {
      locations: (locationsResult.data ?? []).map((row): InventoryLocationView => ({
        id: row.id as string,
        name: row.name as string,
        kind: row.kind as string,
      })),
      items: (itemsResult.data ?? []).map((row): InventoryItemView => ({
        id: row.id as string,
        name: (row.name as string | null) ?? "(unnamed)",
        locationName: (row.inventory_locations as { name?: string } | null)?.name ?? null,
        quantity: row.quantity === null ? null : Number(row.quantity),
        unit: row.unit as string | null,
        level: row.level as InventoryItemView["level"],
        expiresOn: row.expires_on as string | null,
        openedOn: row.opened_on as string | null,
        notes: row.notes as string | null,
      })),
    };
  }

  private static inventoryItemFromRow(
    row: Record<string, unknown>,
    locationName: string | null,
  ): InventoryItemView {
    return {
      id: row.id as string,
      name: (row.name as string | null) ?? "(unnamed)",
      locationName,
      quantity: row.quantity === null ? null : Number(row.quantity as number | null),
      unit: row.unit as string | null,
      level: row.level as InventoryItemView["level"],
      expiresOn: row.expires_on as string | null,
      openedOn: row.opened_on as string | null,
      notes: row.notes as string | null,
    };
  }

  async addInventoryItem(
    householdId: string,
    item: NewInventoryItem,
  ): Promise<InventoryItemView> {
    const { data, error } = await this.userClient.rpc("foodie_add_inventory_item", {
      p_household: householdId,
      p_name: item.name,
      p_location_name: item.locationName ?? null,
      p_quantity: item.quantity ?? null,
      p_unit: item.unit ?? null,
      p_level: item.level ?? null,
      p_expires_on: item.expiresOn ?? null,
      p_notes: item.notes ?? null,
    });
    if (error) throw mapDbError(error, "could not add the inventory item");
    // The RPC returns the raw row (location_id, not a resolved name); the
    // caller supplied the location name, so echo it back directly rather
    // than issuing a second round-trip to resolve it.
    return SupabaseFoodieDb.inventoryItemFromRow(data, item.locationName ?? null);
  }

  async updateInventoryItem(
    householdId: string,
    itemId: string,
    patch: InventoryItemPatch,
  ): Promise<InventoryItemView> {
    const { data, error } = await this.userClient.rpc("foodie_update_inventory_item", {
      p_household: householdId,
      p_item_id: itemId,
      p_quantity: patch.quantity ?? null,
      p_unit: patch.unit ?? null,
      p_level: patch.level ?? null,
      p_expires_on: patch.expiresOn ?? null,
      p_opened_on: patch.openedOn ?? null,
      p_notes: patch.notes ?? null,
    });
    if (error) throw mapDbError(error, "could not update the inventory item");
    const locationName = data.location_id
      ? await this.resolveLocationName(data.location_id as string)
      : null;
    return SupabaseFoodieDb.inventoryItemFromRow(data, locationName);
  }

  async removeInventoryItem(householdId: string, itemId: string): Promise<InventoryItemView> {
    const { data, error } = await this.userClient.rpc("foodie_remove_inventory_item", {
      p_household: householdId,
      p_item_id: itemId,
    });
    if (error) throw mapDbError(error, "could not remove the inventory item");
    const locationName = data.location_id
      ? await this.resolveLocationName(data.location_id as string)
      : null;
    return SupabaseFoodieDb.inventoryItemFromRow(data, locationName);
  }

  private async resolveLocationName(locationId: string): Promise<string | null> {
    const { data } = await this.userClient
      .from("inventory_locations")
      .select("name")
      .eq("id", locationId)
      .maybeSingle();
    return (data?.name as string | undefined) ?? null;
  }

  async getCleaningStatus(householdId: string): Promise<CleaningStatusView> {
    const [tasksResult, completionsResult] = await Promise.all([
      this.userClient
        .from("cleaning_tasks")
        .select(
          "id, name, area, supplies_needed, recurrence_rules(interval_unit, interval_count, weekday, anchor_date), profiles(display_name)",
        )
        .eq("household_id", householdId)
        .eq("is_active", true)
        .is("deleted_at", null)
        .order("created_at"),
      this.userClient
        .from("cleaning_completions")
        .select("task_id, completed_at")
        .eq("household_id", householdId)
        .eq("outcome", "completed")
        .order("completed_at", { ascending: false }),
    ]);
    if (tasksResult.error) throw mapDbError(tasksResult.error, "could not load cleaning tasks");
    if (completionsResult.error) {
      throw mapDbError(completionsResult.error, "could not load cleaning history");
    }

    const lastCompletedByTask = new Map<string, string>();
    for (const row of completionsResult.data ?? []) {
      const taskId = row.task_id as string;
      if (!lastCompletedByTask.has(taskId)) {
        lastCompletedByTask.set(taskId, (row.completed_at as string).slice(0, 10));
      }
    }

    const today = new Date();
    const tasks = (tasksResult.data ?? []).map((row: Record<string, unknown>): CleaningTaskView => {
      const rule = row.recurrence_rules as {
        interval_unit: "day" | "week" | "month" | "year";
        interval_count: number;
        weekday: number | null;
        anchor_date: string | null;
      } | null;
      const lastCompletedOn = lastCompletedByTask.get(row.id as string) ?? null;
      let nextDueOn: string | null = null;
      if (rule) {
        const due = computeCleaningDueDate({
          rule: {
            intervalUnit: rule.interval_unit,
            intervalCount: rule.interval_count,
            weekday: rule.weekday,
            anchorDate: rule.anchor_date,
          },
          lastCompletedOn,
          today,
        });
        nextDueOn = due.toISOString().slice(0, 10);
      }
      return {
        id: row.id as string,
        name: row.name as string,
        area: row.area as string | null,
        recurrence: rule
          ? { intervalUnit: rule.interval_unit, intervalCount: rule.interval_count, weekday: rule.weekday }
          : null,
        assignedUserName: (row.profiles as { display_name?: string } | null)?.display_name ?? null,
        suppliesNeeded: (row.supplies_needed as string[] | null) ?? [],
        nextDueOn,
        overdue: nextDueOn !== null && isOverdue(new Date(nextDueOn), today),
        lastCompletedOn,
      };
    });
    return { tasks };
  }

  async completeCleaningTask(
    householdId: string,
    taskId: string,
    notes?: string,
  ): Promise<CleaningCompletionRecord> {
    const { data, error } = await this.userClient.rpc("foodie_complete_cleaning_task", {
      p_household: householdId,
      p_task_id: taskId,
      p_notes: notes ?? null,
    });
    if (error) throw mapDbError(error, "could not complete the cleaning task");
    const taskName = await this.resolveCleaningTaskName(taskId);
    return {
      taskId,
      taskName,
      outcome: data.outcome as CleaningCompletionRecord["outcome"],
      notes: data.notes as string | null,
    };
  }

  async skipCleaningTask(
    householdId: string,
    taskId: string,
    reason?: string,
  ): Promise<CleaningCompletionRecord> {
    const { data, error } = await this.userClient.rpc("foodie_skip_cleaning_task", {
      p_household: householdId,
      p_task_id: taskId,
      p_reason: reason ?? null,
    });
    if (error) throw mapDbError(error, "could not skip the cleaning task");
    const taskName = await this.resolveCleaningTaskName(taskId);
    return {
      taskId,
      taskName,
      outcome: data.outcome as CleaningCompletionRecord["outcome"],
      notes: data.notes as string | null,
    };
  }

  private async resolveCleaningTaskName(taskId: string): Promise<string> {
    const { data } = await this.userClient
      .from("cleaning_tasks")
      .select("name")
      .eq("id", taskId)
      .maybeSingle();
    return (data?.name as string | undefined) ?? "(unknown task)";
  }

  async getFilterStatus(householdId: string): Promise<FilterStatusView> {
    const [componentsResult, replacementsResult] = await Promise.all([
      this.userClient
        .from("tracked_components")
        .select("id, system_name, component_name, kind, installed_on, replace_interval_days, spares_count")
        .eq("household_id", householdId)
        .is("deleted_at", null)
        .order("system_name"),
      this.userClient
        .from("component_replacements")
        .select("component_id, replaced_on")
        .eq("household_id", householdId)
        .order("replaced_on", { ascending: false }),
    ]);
    if (componentsResult.error) {
      throw mapDbError(componentsResult.error, "could not load tracked components");
    }
    if (replacementsResult.error) {
      throw mapDbError(replacementsResult.error, "could not load replacement history");
    }

    const lastReplacedByComponent = new Map<string, string>();
    for (const row of replacementsResult.data ?? []) {
      const componentId = row.component_id as string;
      if (!lastReplacedByComponent.has(componentId)) {
        lastReplacedByComponent.set(componentId, row.replaced_on as string);
      }
    }

    const today = new Date();
    const components = (componentsResult.data ?? []).map((row): TrackedComponentView => {
      const lastReplacedOn = lastReplacedByComponent.get(row.id as string) ?? null;
      const due = computeComponentDueDate({
        replaceIntervalDays: row.replace_interval_days as number | null,
        lastReplacedOn,
        installedOn: row.installed_on as string | null,
      });
      const nextDueOn = due ? due.toISOString().slice(0, 10) : null;
      return {
        id: row.id as string,
        systemName: row.system_name as string,
        componentName: row.component_name as string,
        kind: row.kind as string,
        sparesCount: row.spares_count as number,
        nextDueOn,
        overdue: nextDueOn !== null && isOverdue(new Date(nextDueOn), today),
        lastReplacedOn,
      };
    });
    return { components };
  }

  async logFilterReplacement(
    householdId: string,
    componentId: string,
    notes?: string,
  ): Promise<TrackedComponentView> {
    const { error } = await this.userClient.rpc("foodie_log_filter_replacement", {
      p_household: householdId,
      p_component_id: componentId,
      p_notes: notes ?? null,
    });
    if (error) throw mapDbError(error, "could not log the filter replacement");
    const { data: component, error: componentError } = await this.userClient
      .from("tracked_components")
      .select("id, system_name, component_name, kind, installed_on, replace_interval_days, spares_count")
      .eq("id", componentId)
      .single();
    if (componentError) {
      throw mapDbError(componentError, "could not reload the tracked component");
    }
    const due = computeComponentDueDate({
      replaceIntervalDays: component.replace_interval_days as number | null,
      lastReplacedOn: new Date().toISOString().slice(0, 10),
      installedOn: component.installed_on as string | null,
    });
    const nextDueOn = due ? due.toISOString().slice(0, 10) : null;
    return {
      id: component.id as string,
      systemName: component.system_name as string,
      componentName: component.component_name as string,
      kind: component.kind as string,
      sparesCount: component.spares_count as number,
      nextDueOn,
      overdue: false,
      lastReplacedOn: new Date().toISOString().slice(0, 10),
    };
  }

  async getMaintenanceIssues(
    householdId: string,
    status?: MaintenanceIssueStatus,
  ): Promise<MaintenanceIssueView[]> {
    let query = this.userClient
      .from("maintenance_issues")
      .select("id, title, area, description, status, reported_at, resolved_at, notes")
      .eq("household_id", householdId)
      .is("deleted_at", null)
      .order("reported_at", { ascending: false });
    if (status) query = query.eq("status", status);
    const { data, error } = await query;
    if (error) throw mapDbError(error, "could not load maintenance issues");
    return (data ?? []).map((row): MaintenanceIssueView => ({
      id: row.id as string,
      title: row.title as string,
      area: row.area as string | null,
      description: row.description as string | null,
      status: row.status as MaintenanceIssueStatus,
      reportedAt: row.reported_at as string,
      resolvedAt: row.resolved_at as string | null,
      notes: row.notes as string | null,
    }));
  }

  async reportMaintenanceIssue(
    householdId: string,
    issue: { title: string; area?: string; description?: string },
  ): Promise<MaintenanceIssueView> {
    const { data, error } = await this.userClient.rpc("foodie_report_maintenance_issue", {
      p_household: householdId,
      p_title: issue.title,
      p_area: issue.area ?? null,
      p_description: issue.description ?? null,
    });
    if (error) throw mapDbError(error, "could not report the maintenance issue");
    return SupabaseFoodieDb.maintenanceIssueFromRow(data);
  }

  async resolveMaintenanceIssue(
    householdId: string,
    issueId: string,
    notes?: string,
  ): Promise<MaintenanceIssueView> {
    const { data, error } = await this.userClient.rpc("foodie_resolve_maintenance_issue", {
      p_household: householdId,
      p_issue_id: issueId,
      p_notes: notes ?? null,
    });
    if (error) throw mapDbError(error, "could not resolve the maintenance issue");
    return SupabaseFoodieDb.maintenanceIssueFromRow(data);
  }

  private static maintenanceIssueFromRow(row: Record<string, unknown>): MaintenanceIssueView {
    return {
      id: row.id as string,
      title: row.title as string,
      area: row.area as string | null,
      description: row.description as string | null,
      status: row.status as MaintenanceIssueStatus,
      reportedAt: row.reported_at as string,
      resolvedAt: row.resolved_at as string | null,
      notes: row.notes as string | null,
    };
  }

  private static fermentationProjectFromRow(row: Record<string, unknown>): FermentationProjectView {
    return {
      id: row.id as string,
      projectType: row.project_type as string,
      name: row.name as string,
      status: row.status as FermentationStatus,
      startedAt: row.started_at as string,
      endedAt: row.ended_at as string | null,
      currentStage: row.current_stage as string | null,
      targetParams: (row.target_params as Record<string, unknown> | null) ?? null,
      nextCheckAt: row.next_check_at as string | null,
      notes: row.notes as string | null,
    };
  }

  private static fermentationLogFromRow(row: Record<string, unknown>): FermentationLogView {
    return {
      id: row.id as string,
      projectId: row.project_id as string,
      loggedAt: row.logged_at as string,
      logType: row.log_type as FermentationLogType,
      payload: (row.payload as Record<string, unknown> | null) ?? null,
      notes: row.notes as string | null,
      author: row.author as string,
    };
  }

  async listFermentationProjects(
    householdId: string,
    status?: FermentationStatus,
  ): Promise<FermentationProjectView[]> {
    let query = this.userClient
      .from("fermentation_projects")
      .select(
        "id, project_type, name, status, started_at, ended_at, current_stage, target_params, next_check_at, notes",
      )
      .eq("household_id", householdId)
      .is("deleted_at", null);
    query = status ? query.eq("status", status) : query.eq("status", "active");
    const { data, error } = await query.order("started_at", { ascending: false });
    if (error) throw mapDbError(error, "could not load fermentation projects");
    return (data ?? []).map(SupabaseFoodieDb.fermentationProjectFromRow);
  }

  async getFermentationProject(
    householdId: string,
    projectId: string,
  ): Promise<FermentationProjectDetail> {
    const [projectResult, logsResult] = await Promise.all([
      this.userClient
        .from("fermentation_projects")
        .select(
          "id, project_type, name, status, started_at, ended_at, current_stage, target_params, next_check_at, notes",
        )
        .eq("id", projectId)
        .eq("household_id", householdId)
        .is("deleted_at", null)
        .maybeSingle(),
      this.userClient
        .from("fermentation_logs")
        .select("id, project_id, logged_at, log_type, payload, notes, author")
        .eq("household_id", householdId)
        .eq("project_id", projectId)
        .order("logged_at", { ascending: false }),
    ]);
    if (projectResult.error) {
      throw mapDbError(projectResult.error, "could not load the fermentation project");
    }
    if (!projectResult.data) {
      throw new FoodieError("not_found", "fermentation project not found");
    }
    if (logsResult.error) {
      throw mapDbError(logsResult.error, "could not load fermentation logs");
    }
    return {
      project: SupabaseFoodieDb.fermentationProjectFromRow(projectResult.data),
      logs: (logsResult.data ?? []).map(SupabaseFoodieDb.fermentationLogFromRow),
    };
  }

  async logFermentationEvent(
    householdId: string,
    projectId: string,
    logType: FermentationLogType,
    payload?: Record<string, unknown>,
    notes?: string,
  ): Promise<FermentationLogView> {
    const { data, error } = await this.userClient.rpc("foodie_log_fermentation_event", {
      p_household: householdId,
      p_project_id: projectId,
      p_log_type: logType,
      p_payload: payload ?? null,
      p_notes: notes ?? null,
    });
    if (error) throw mapDbError(error, "could not log the fermentation event");
    return SupabaseFoodieDb.fermentationLogFromRow(data);
  }

  async logSourdoughFeeding(
    householdId: string,
    projectId: string,
    feeding: {
      starterG: number;
      flourG: number;
      waterG: number;
      flourType?: string;
      discardG?: number;
      notes?: string;
    },
  ): Promise<FermentationLogView> {
    const { data, error } = await this.userClient.rpc("foodie_log_sourdough_feeding", {
      p_household: householdId,
      p_project_id: projectId,
      p_starter_g: feeding.starterG,
      p_flour_g: feeding.flourG,
      p_water_g: feeding.waterG,
      p_flour_type: feeding.flourType ?? null,
      p_discard_g: feeding.discardG ?? null,
      p_notes: feeding.notes ?? null,
    });
    if (error) throw mapDbError(error, "could not log the sourdough feeding");
    return SupabaseFoodieDb.fermentationLogFromRow(data);
  }

  async updateFermentationStage(
    householdId: string,
    projectId: string,
    update: {
      currentStage?: string;
      status?: FermentationStatus;
      nextCheckAt?: string;
      notes?: string;
    },
  ): Promise<FermentationProjectView> {
    const { data, error } = await this.userClient.rpc("foodie_update_fermentation_stage", {
      p_household: householdId,
      p_project_id: projectId,
      p_current_stage: update.currentStage ?? null,
      p_status: update.status ?? null,
      p_next_check_at: update.nextCheckAt ?? null,
      p_notes: update.notes ?? null,
    });
    if (error) throw mapDbError(error, "could not update the fermentation project");
    return SupabaseFoodieDb.fermentationProjectFromRow(data);
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
