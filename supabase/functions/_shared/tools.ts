// Foodie's tool registry — the ONLY capabilities the model has. Each tool
// validates its input, is executed against the narrow FoodieDb interface
// (user-JWT + RLS underneath), and reports a human-readable summary that
// feeds the intent-level audit (agent_actions).
//
// Stream 3 set (deliberately small):
//   get_basic_household_context, get_household_preferences,
//   save_household_preference, get_grocery_list, add_grocery_item
// Household Inventory phase adds:
//   get_inventory, add_inventory_item, update_inventory_item,
//   remove_inventory_item
// Cleaning + Home Care phase adds:
//   get_cleaning_status, complete_cleaning_task, skip_cleaning_task,
//   get_filter_status, log_filter_replacement, get_maintenance_issues,
//   report_maintenance_issue, resolve_maintenance_issue
// Fermentation Tracking phase adds:
//   get_fermentation_projects, get_fermentation_project,
//   log_fermentation_event, log_sourdough_feeding, update_fermentation_stage
// Later streams REGISTER new tools here; nothing else widens agent access.

import type {
  FermentationLogType,
  FermentationStatus,
  FoodieDb,
  MaintenanceIssueStatus,
  ToolSpec,
} from "./types.ts";

export type Validation =
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; error: string };

export interface ToolOutcome {
  /** One-line, safe summary for the audit trail and the client's action list. */
  summary: string;
  /** Structured data returned to the model as the tool result. */
  data: unknown;
}

export interface ToolContext {
  db: FoodieDb;
  householdId: string;
  userId: string;
}

export interface ToolDefinition {
  spec: ToolSpec;
  mutating: boolean;
  validate(input: unknown): Validation;
  execute(ctx: ToolContext, input: Record<string, unknown>): Promise<ToolOutcome>;
}

// ---------------------------------------------------------------------------
// Small hand-rolled validators (structured errors, no dependencies).
// ---------------------------------------------------------------------------

function asObject(input: unknown): Record<string, unknown> | null {
  return typeof input === "object" && input !== null && !Array.isArray(input)
    ? (input as Record<string, unknown>)
    : null;
}

function requireString(
  obj: Record<string, unknown>,
  field: string,
  maxLength: number,
): string | { error: string } {
  const v = obj[field];
  if (typeof v !== "string" || v.trim().length === 0) {
    return { error: `"${field}" must be a non-empty string` };
  }
  if (v.length > maxLength) {
    return { error: `"${field}" must be at most ${maxLength} characters` };
  }
  return v.trim();
}

function optionalNumber(
  obj: Record<string, unknown>,
  field: string,
): number | undefined | { error: string } {
  const v = obj[field];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 100000) {
    return { error: `"${field}" must be a number between 0 and 100000` };
  }
  return v;
}

function requirePositiveNumber(
  obj: Record<string, unknown>,
  field: string,
): number | { error: string } {
  const v = obj[field];
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0 || v > 100000) {
    return { error: `"${field}" must be a number greater than 0 (and at most 100000)` };
  }
  return v;
}

function optionalString(
  obj: Record<string, unknown>,
  field: string,
  maxLength: number,
): string | undefined | { error: string } {
  const v = obj[field];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string") return { error: `"${field}" must be a string` };
  if (v.length > maxLength) {
    return { error: `"${field}" must be at most ${maxLength} characters` };
  }
  const trimmed = v.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function optionalPlainObject(
  obj: Record<string, unknown>,
  field: string,
): Record<string, unknown> | undefined | { error: string } {
  const v = obj[field];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "object" || Array.isArray(v)) {
    return { error: `"${field}" must be an object` };
  }
  return v as Record<string, unknown>;
}

function isError(v: unknown): v is { error: string } {
  return typeof v === "object" && v !== null && "error" in v;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function optionalDate(
  obj: Record<string, unknown>,
  field: string,
): string | undefined | { error: string } {
  const v = obj[field];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string" || !ISO_DATE.test(v) || Number.isNaN(Date.parse(v))) {
    return { error: `"${field}" must be a date in YYYY-MM-DD format` };
  }
  return v;
}

const SUPPLY_LEVELS = ["full", "good", "low", "almost_empty", "out"] as const;
const MAINTENANCE_STATUSES = ["open", "in_progress", "resolved"] as const;
const FERMENTATION_STATUSES = ["planned", "active", "paused", "completed", "discarded"] as const;
// Deliberately excludes 'feeding' (its own tool: log_sourdough_feeding) and
// 'stage_change' (its own tool: update_fermentation_stage, which records
// the stage_change log automatically) — this generic tool is for
// observations/turns/temperature checks, not the specialized events.
const GENERIC_FERMENTATION_LOG_TYPES = ["observation", "turning", "temperature"] as const;

function optionalEnum<T extends string>(
  obj: Record<string, unknown>,
  field: string,
  allowed: readonly T[],
): T | undefined | { error: string } {
  const v = obj[field];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
    return { error: `"${field}" must be one of: ${allowed.join(", ")}` };
  }
  return v as T;
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const getBasicHouseholdContext: ToolDefinition = {
  spec: {
    name: "get_basic_household_context",
    description:
      "Get basic information about the household: its name, timezone, and member names.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => {
    const obj = asObject(input) ?? {};
    return { ok: true, value: obj };
  },
  execute: async (ctx) => {
    const context = await ctx.db.getBasicContext(ctx.householdId);
    return { summary: "Read basic household context", data: context };
  },
};

const getHouseholdPreferences: ToolDefinition = {
  spec: {
    name: "get_household_preferences",
    description:
      "List the household's stored durable preferences (e.g. shopping day, reminder tone, meal variety).",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => ({ ok: true, value: asObject(input) ?? {} }),
  execute: async (ctx) => {
    const memories = await ctx.db.listMemories(ctx.householdId, ["preference"]);
    return { summary: "Read household preferences", data: { preferences: memories } };
  },
};

const saveHouseholdPreference: ToolDefinition = {
  spec: {
    name: "save_household_preference",
    description:
      "Save or update ONE durable household preference. Use only when the user " +
      "states something clearly meant to persist (e.g. 'we prefer grocery shopping " +
      "on Sundays'), and tell the user you saved it. `key` is a short stable " +
      "dot-namespaced identifier such as 'grocery.shopping_day' or 'reminders.tone'; " +
      "reusing an existing key updates that preference.",
    inputSchema: {
      type: "object",
      properties: {
        key: { type: "string", description: "Stable identifier, e.g. 'grocery.shopping_day'" },
        content: { type: "string", description: "The preference, as one clear sentence" },
      },
      required: ["key", "content"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const key = requireString(obj, "key", 200);
    if (isError(key)) return { ok: false, error: key.error };
    const content = requireString(obj, "content", 2000);
    if (isError(content)) return { ok: false, error: content.error };
    return { ok: true, value: { key, content } };
  },
  execute: async (ctx, input) => {
    const memory = await ctx.db.saveMemory(
      ctx.householdId,
      "preference",
      input.key as string,
      input.content as string,
    );
    return {
      summary: `Saved preference ${memory.key}`,
      data: { saved: memory },
    };
  },
};

const getGroceryList: ToolDefinition = {
  spec: {
    name: "get_grocery_list",
    description: "Get the household's current grocery list with all items.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => ({ ok: true, value: asObject(input) ?? {} }),
  execute: async (ctx) => {
    const list = await ctx.db.getGroceryList(ctx.householdId);
    return { summary: "Read the grocery list", data: list };
  },
};

const addGroceryItem: ToolDefinition = {
  spec: {
    name: "add_grocery_item",
    description:
      "Add ONE item to the household's grocery list. Only report the item as " +
      "added after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Item name, e.g. 'Greek yogurt'" },
        quantity: { type: "number", description: "Optional amount" },
        unit: { type: "string", description: "Optional unit, e.g. 'l', 'kg', 'pack'" },
        notes: { type: "string", description: "Optional note, e.g. brand or size" },
      },
      required: ["name"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const name = requireString(obj, "name", 200);
    if (isError(name)) return { ok: false, error: name.error };
    const quantity = optionalNumber(obj, "quantity");
    if (isError(quantity)) return { ok: false, error: quantity.error };
    const unit = optionalString(obj, "unit", 40);
    if (isError(unit)) return { ok: false, error: unit.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { name };
    if (quantity !== undefined) value.quantity = quantity;
    if (unit !== undefined) value.unit = unit;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const item = await ctx.db.addGroceryItem(ctx.householdId, {
      name: input.name as string,
      quantity: input.quantity as number | undefined,
      unit: input.unit as string | undefined,
      notes: input.notes as string | undefined,
    });
    return {
      summary: `Added "${item.name}" to the grocery list`,
      data: { added: item },
    };
  },
};

const getInventory: ToolDefinition = {
  spec: {
    name: "get_inventory",
    description:
      "Get the household's current pantry/fridge/freezer inventory: all locations " +
      "and all items, with quantities, units, approximate levels, and expiry dates " +
      "where known. Call this before updating or removing an item to find its id.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => ({ ok: true, value: asObject(input) ?? {} }),
  execute: async (ctx) => {
    const inventory = await ctx.db.getInventory(ctx.householdId);
    return { summary: "Read the household inventory", data: inventory };
  },
};

const addInventoryItem: ToolDefinition = {
  spec: {
    name: "add_inventory_item",
    description:
      "Add ONE item to the household's pantry/fridge/freezer inventory. Only report " +
      "the item as added after this tool succeeds. `location` is a place like " +
      "'Fridge' or 'Pantry' — it's created automatically if it doesn't exist yet. " +
      "Use `quantity`+`unit` when a precise amount is known; use `level` " +
      "(full/good/low/almost_empty/out) when it isn't.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Item name, e.g. 'Milk'" },
        location: { type: "string", description: "Optional location, e.g. 'Fridge'" },
        quantity: { type: "number", description: "Optional precise amount" },
        unit: { type: "string", description: "Optional unit, e.g. 'l', 'kg', 'piece'" },
        level: {
          type: "string",
          enum: [...SUPPLY_LEVELS],
          description: "Optional approximate level, when an exact quantity isn't known",
        },
        expires_on: { type: "string", description: "Optional expiry date, YYYY-MM-DD" },
        notes: { type: "string", description: "Optional note" },
      },
      required: ["name"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const name = requireString(obj, "name", 200);
    if (isError(name)) return { ok: false, error: name.error };
    const location = optionalString(obj, "location", 100);
    if (isError(location)) return { ok: false, error: location.error };
    const quantity = optionalNumber(obj, "quantity");
    if (isError(quantity)) return { ok: false, error: quantity.error };
    const unit = optionalString(obj, "unit", 40);
    if (isError(unit)) return { ok: false, error: unit.error };
    const level = optionalEnum(obj, "level", SUPPLY_LEVELS);
    if (isError(level)) return { ok: false, error: level.error };
    const expiresOn = optionalDate(obj, "expires_on");
    if (isError(expiresOn)) return { ok: false, error: expiresOn.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { name };
    if (location !== undefined) value.location = location;
    if (quantity !== undefined) value.quantity = quantity;
    if (unit !== undefined) value.unit = unit;
    if (level !== undefined) value.level = level;
    if (expiresOn !== undefined) value.expiresOn = expiresOn;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const item = await ctx.db.addInventoryItem(ctx.householdId, {
      name: input.name as string,
      locationName: input.location as string | undefined,
      quantity: input.quantity as number | undefined,
      unit: input.unit as string | undefined,
      level: input.level as never,
      expiresOn: input.expiresOn as string | undefined,
      notes: input.notes as string | undefined,
    });
    return {
      summary: `Added "${item.name}" to inventory${item.locationName ? ` (${item.locationName})` : ""}`,
      data: { added: item },
    };
  },
};

const updateInventoryItem: ToolDefinition = {
  spec: {
    name: "update_inventory_item",
    description:
      "Update ONE existing inventory item, found by its id (call get_inventory " +
      "first). Only the fields you provide are changed — omitted fields are left " +
      "as they are; this call cannot clear a field back to empty. Only report the " +
      "update as done after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        item_id: { type: "string", description: "The inventory item's id, from get_inventory" },
        quantity: { type: "number", description: "New precise amount" },
        unit: { type: "string", description: "New unit, e.g. 'l', 'kg', 'piece'" },
        level: { type: "string", enum: [...SUPPLY_LEVELS], description: "New approximate level" },
        expires_on: { type: "string", description: "New expiry date, YYYY-MM-DD" },
        opened_on: { type: "string", description: "Date it was opened, YYYY-MM-DD" },
        notes: { type: "string", description: "New note" },
      },
      required: ["item_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const itemId = requireString(obj, "item_id", 100);
    if (isError(itemId)) return { ok: false, error: itemId.error };
    const quantity = optionalNumber(obj, "quantity");
    if (isError(quantity)) return { ok: false, error: quantity.error };
    const unit = optionalString(obj, "unit", 40);
    if (isError(unit)) return { ok: false, error: unit.error };
    const level = optionalEnum(obj, "level", SUPPLY_LEVELS);
    if (isError(level)) return { ok: false, error: level.error };
    const expiresOn = optionalDate(obj, "expires_on");
    if (isError(expiresOn)) return { ok: false, error: expiresOn.error };
    const openedOn = optionalDate(obj, "opened_on");
    if (isError(openedOn)) return { ok: false, error: openedOn.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    if (
      quantity === undefined && unit === undefined && level === undefined &&
      expiresOn === undefined && openedOn === undefined && notes === undefined
    ) {
      return { ok: false, error: "at least one field to update must be provided" };
    }
    const value: Record<string, unknown> = { itemId };
    if (quantity !== undefined) value.quantity = quantity;
    if (unit !== undefined) value.unit = unit;
    if (level !== undefined) value.level = level;
    if (expiresOn !== undefined) value.expiresOn = expiresOn;
    if (openedOn !== undefined) value.openedOn = openedOn;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const item = await ctx.db.updateInventoryItem(ctx.householdId, input.itemId as string, {
      quantity: input.quantity as number | undefined,
      unit: input.unit as string | undefined,
      level: input.level as never,
      expiresOn: input.expiresOn as string | undefined,
      openedOn: input.openedOn as string | undefined,
      notes: input.notes as string | undefined,
    });
    return {
      summary: `Updated "${item.name}" in inventory`,
      data: { updated: item },
    };
  },
};

const removeInventoryItem: ToolDefinition = {
  spec: {
    name: "remove_inventory_item",
    description:
      "Remove ONE item from the household's inventory — use this when the user says " +
      "something is used up, thrown out, or otherwise gone (e.g. 'we used the last " +
      "onion'). Found by its id (call get_inventory first if you don't already have " +
      "it). Only report the item as removed after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        item_id: { type: "string", description: "The inventory item's id, from get_inventory" },
      },
      required: ["item_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const itemId = requireString(obj, "item_id", 100);
    if (isError(itemId)) return { ok: false, error: itemId.error };
    return { ok: true, value: { itemId } };
  },
  execute: async (ctx, input) => {
    const item = await ctx.db.removeInventoryItem(ctx.householdId, input.itemId as string);
    return {
      summary: `Removed "${item.name}" from inventory`,
      data: { removed: item },
    };
  },
};

const getCleaningStatus: ToolDefinition = {
  spec: {
    name: "get_cleaning_status",
    description:
      "Get the household's cleaning tasks: area, recurrence, who's assigned, " +
      "supplies needed, when each is next due, whether it's overdue, and when " +
      "it was last completed. Call this before completing or skipping a task " +
      "to find its id.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => ({ ok: true, value: asObject(input) ?? {} }),
  execute: async (ctx) => {
    const status = await ctx.db.getCleaningStatus(ctx.householdId);
    return { summary: "Read cleaning status", data: status };
  },
};

const completeCleaningTask: ToolDefinition = {
  spec: {
    name: "complete_cleaning_task",
    description:
      "Mark ONE cleaning task as completed just now, found by its id (call " +
      "get_cleaning_status first). Only report the task as done after this " +
      "tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "The cleaning task's id, from get_cleaning_status" },
        notes: { type: "string", description: "Optional note about the completion" },
      },
      required: ["task_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const taskId = requireString(obj, "task_id", 100);
    if (isError(taskId)) return { ok: false, error: taskId.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { taskId };
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const result = await ctx.db.completeCleaningTask(
      ctx.householdId,
      input.taskId as string,
      input.notes as string | undefined,
    );
    return {
      summary: `Marked "${result.taskName}" as completed`,
      data: { completed: result },
    };
  },
};

const skipCleaningTask: ToolDefinition = {
  spec: {
    name: "skip_cleaning_task",
    description:
      "Mark ONE cleaning task as skipped for now, found by its id (call " +
      "get_cleaning_status first). It will roll over to the household's next " +
      "cleaning day. Only report the task as skipped after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "The cleaning task's id, from get_cleaning_status" },
        reason: { type: "string", description: "Optional reason for skipping" },
      },
      required: ["task_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const taskId = requireString(obj, "task_id", 100);
    if (isError(taskId)) return { ok: false, error: taskId.error };
    const reason = optionalString(obj, "reason", 500);
    if (isError(reason)) return { ok: false, error: reason.error };
    const value: Record<string, unknown> = { taskId };
    if (reason !== undefined) value.reason = reason;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const result = await ctx.db.skipCleaningTask(
      ctx.householdId,
      input.taskId as string,
      input.reason as string | undefined,
    );
    return {
      summary: `Marked "${result.taskName}" as skipped`,
      data: { skipped: result },
    };
  },
};

const getFilterStatus: ToolDefinition = {
  spec: {
    name: "get_filter_status",
    description:
      "Get the household's tracked replaceable components (filters, batteries, " +
      "cartridges, etc.): system, spares on hand, when each is next due for " +
      "replacement, and whether it's overdue. Call this before logging a " +
      "replacement to find its id.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  mutating: false,
  validate: (input) => ({ ok: true, value: asObject(input) ?? {} }),
  execute: async (ctx) => {
    const status = await ctx.db.getFilterStatus(ctx.householdId);
    return { summary: "Read filter/component status", data: status };
  },
};

const logFilterReplacement: ToolDefinition = {
  spec: {
    name: "log_filter_replacement",
    description:
      "Log that ONE tracked component (filter, battery, cartridge, etc.) was " +
      "just replaced, found by its id (call get_filter_status first). Reduces " +
      "its spares count by one. Only report it as replaced after this tool " +
      "succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        component_id: { type: "string", description: "The component's id, from get_filter_status" },
        notes: { type: "string", description: "Optional note" },
      },
      required: ["component_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const componentId = requireString(obj, "component_id", 100);
    if (isError(componentId)) return { ok: false, error: componentId.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { componentId };
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const component = await ctx.db.logFilterReplacement(
      ctx.householdId,
      input.componentId as string,
      input.notes as string | undefined,
    );
    return {
      summary: `Logged replacement of "${component.componentName}" (${component.systemName})`,
      data: { component },
    };
  },
};

const getMaintenanceIssues: ToolDefinition = {
  spec: {
    name: "get_maintenance_issues",
    description:
      "List the household's apartment maintenance issues/needs, optionally " +
      "filtered by status. Call this before resolving an issue to find its id.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: [...MAINTENANCE_STATUSES],
          description: "Optional filter: only issues in this status",
        },
      },
      additionalProperties: false,
    },
  },
  mutating: false,
  validate: (input) => {
    const obj = asObject(input) ?? {};
    const status = optionalEnum(obj, "status", MAINTENANCE_STATUSES);
    if (isError(status)) return { ok: false, error: status.error };
    const value: Record<string, unknown> = {};
    if (status !== undefined) value.status = status;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const issues = await ctx.db.getMaintenanceIssues(
      ctx.householdId,
      input.status as MaintenanceIssueStatus | undefined,
    );
    return { summary: "Read maintenance issues", data: { issues } };
  },
};

const reportMaintenanceIssue: ToolDefinition = {
  spec: {
    name: "report_maintenance_issue",
    description:
      "Report ONE new apartment maintenance issue or need (e.g. a leak, a " +
      "broken appliance, something that needs fixing). Only report it as " +
      "logged after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short title, e.g. 'Leaky faucet'" },
        area: { type: "string", description: "Optional area/room, e.g. 'Kitchen'" },
        description: { type: "string", description: "Optional longer description" },
      },
      required: ["title"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const title = requireString(obj, "title", 200);
    if (isError(title)) return { ok: false, error: title.error };
    const area = optionalString(obj, "area", 100);
    if (isError(area)) return { ok: false, error: area.error };
    const description = optionalString(obj, "description", 2000);
    if (isError(description)) return { ok: false, error: description.error };
    const value: Record<string, unknown> = { title };
    if (area !== undefined) value.area = area;
    if (description !== undefined) value.description = description;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const issue = await ctx.db.reportMaintenanceIssue(ctx.householdId, {
      title: input.title as string,
      area: input.area as string | undefined,
      description: input.description as string | undefined,
    });
    return {
      summary: `Reported maintenance issue "${issue.title}"`,
      data: { reported: issue },
    };
  },
};

const resolveMaintenanceIssue: ToolDefinition = {
  spec: {
    name: "resolve_maintenance_issue",
    description:
      "Mark ONE maintenance issue as resolved, found by its id (call " +
      "get_maintenance_issues first). Only report it as resolved after this " +
      "tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        issue_id: { type: "string", description: "The issue's id, from get_maintenance_issues" },
        notes: { type: "string", description: "Optional resolution note" },
      },
      required: ["issue_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const issueId = requireString(obj, "issue_id", 100);
    if (isError(issueId)) return { ok: false, error: issueId.error };
    const notes = optionalString(obj, "notes", 500);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { issueId };
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const issue = await ctx.db.resolveMaintenanceIssue(
      ctx.householdId,
      input.issueId as string,
      input.notes as string | undefined,
    );
    return {
      summary: `Resolved maintenance issue "${issue.title}"`,
      data: { resolved: issue },
    };
  },
};

const getFermentationProjects: ToolDefinition = {
  spec: {
    name: "get_fermentation_projects",
    description:
      "List the household's fermentation projects (sourdough starters, cacao " +
      "batches, and anything else fermenting). Defaults to active projects " +
      "only; pass a status to see planned/paused/completed/discarded ones. " +
      "Call this before logging an event or updating a project to find its id.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: [...FERMENTATION_STATUSES],
          description: "Optional filter; defaults to 'active' when omitted",
        },
      },
      additionalProperties: false,
    },
  },
  mutating: false,
  validate: (input) => {
    const obj = asObject(input) ?? {};
    const status = optionalEnum(obj, "status", FERMENTATION_STATUSES);
    if (isError(status)) return { ok: false, error: status.error };
    const value: Record<string, unknown> = {};
    if (status !== undefined) value.status = status;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const projects = await ctx.db.listFermentationProjects(
      ctx.householdId,
      input.status as FermentationStatus | undefined,
    );
    return { summary: "Read fermentation projects", data: { projects } };
  },
};

const getFermentationProject: ToolDefinition = {
  spec: {
    name: "get_fermentation_project",
    description:
      "Get ONE fermentation project's full detail, including its complete " +
      "log history (feedings, turns, observations, stage changes) newest " +
      "first — use this to answer questions about a specific starter or batch.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string", description: "The project's id, from get_fermentation_projects" },
      },
      required: ["project_id"],
      additionalProperties: false,
    },
  },
  mutating: false,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const projectId = requireString(obj, "project_id", 100);
    if (isError(projectId)) return { ok: false, error: projectId.error };
    return { ok: true, value: { projectId } };
  },
  execute: async (ctx, input) => {
    const detail = await ctx.db.getFermentationProject(ctx.householdId, input.projectId as string);
    return { summary: `Read fermentation project "${detail.project.name}"`, data: detail };
  },
};

const logFermentationEvent: ToolDefinition = {
  spec: {
    name: "log_fermentation_event",
    description:
      "Log an observation, turn/stir, or temperature check for ONE fermentation " +
      "project, found by its id (call get_fermentation_projects first). Use " +
      "log_sourdough_feeding instead for sourdough feedings, and " +
      "update_fermentation_stage instead for stage/status changes. Only " +
      "report the event as logged after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string", description: "The project's id" },
        log_type: {
          type: "string",
          enum: [...GENERIC_FERMENTATION_LOG_TYPES],
          description: "'temperature' payload example: {\"temp_c\": 31}",
        },
        payload: {
          type: "object",
          description: "Optional structured data, e.g. {\"temp_c\": 31} or {\"turn_number\": 2}",
        },
        notes: { type: "string", description: "Optional free-text note, e.g. smell/appearance" },
      },
      required: ["project_id", "log_type"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const projectId = requireString(obj, "project_id", 100);
    if (isError(projectId)) return { ok: false, error: projectId.error };
    const logType = optionalEnum(obj, "log_type", GENERIC_FERMENTATION_LOG_TYPES);
    if (isError(logType)) return { ok: false, error: logType.error };
    if (logType === undefined) return { ok: false, error: '"log_type" is required' };
    const payload = optionalPlainObject(obj, "payload");
    if (isError(payload)) return { ok: false, error: payload.error };
    const notes = optionalString(obj, "notes", 1000);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { projectId, logType };
    if (payload !== undefined) value.payload = payload;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const log = await ctx.db.logFermentationEvent(
      ctx.householdId,
      input.projectId as string,
      input.logType as FermentationLogType,
      input.payload as Record<string, unknown> | undefined,
      input.notes as string | undefined,
    );
    return { summary: `Logged a ${log.logType} event`, data: { logged: log } };
  },
};

const logSourdoughFeeding: ToolDefinition = {
  spec: {
    name: "log_sourdough_feeding",
    description:
      "Log a sourdough starter feeding for ONE project, found by its id " +
      "(call get_fermentation_projects first). Records the raw amounts; " +
      "hydration and feed ratio are derived from them when read back, not " +
      "asked for here. Only report the feeding as logged after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string", description: "The project's id" },
        starter_g: { type: "number", description: "Starter used, in grams" },
        flour_g: { type: "number", description: "Flour added, in grams" },
        water_g: { type: "number", description: "Water added, in grams" },
        flour_type: { type: "string", description: "Optional, e.g. 'rye', 'bread flour'" },
        discard_g: { type: "number", description: "Optional amount discarded, in grams" },
        notes: { type: "string", description: "Optional note, e.g. rise/peak observations" },
      },
      required: ["project_id", "starter_g", "flour_g", "water_g"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const projectId = requireString(obj, "project_id", 100);
    if (isError(projectId)) return { ok: false, error: projectId.error };
    const starterG = requirePositiveNumber(obj, "starter_g");
    if (isError(starterG)) return { ok: false, error: starterG.error };
    const flourG = requirePositiveNumber(obj, "flour_g");
    if (isError(flourG)) return { ok: false, error: flourG.error };
    const waterG = requirePositiveNumber(obj, "water_g");
    if (isError(waterG)) return { ok: false, error: waterG.error };
    const flourType = optionalString(obj, "flour_type", 50);
    if (isError(flourType)) return { ok: false, error: flourType.error };
    const discardG = optionalNumber(obj, "discard_g");
    if (isError(discardG)) return { ok: false, error: discardG.error };
    const notes = optionalString(obj, "notes", 1000);
    if (isError(notes)) return { ok: false, error: notes.error };
    const value: Record<string, unknown> = { projectId, starterG, flourG, waterG };
    if (flourType !== undefined) value.flourType = flourType;
    if (discardG !== undefined) value.discardG = discardG;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const log = await ctx.db.logSourdoughFeeding(ctx.householdId, input.projectId as string, {
      starterG: input.starterG as number,
      flourG: input.flourG as number,
      waterG: input.waterG as number,
      flourType: input.flourType as string | undefined,
      discardG: input.discardG as number | undefined,
      notes: input.notes as string | undefined,
    });
    return { summary: "Logged a sourdough feeding", data: { logged: log } };
  },
};

const updateFermentationStage: ToolDefinition = {
  spec: {
    name: "update_fermentation_stage",
    description:
      "Update ONE fermentation project's current stage, status, and/or next " +
      "check-in time, found by its id (call get_fermentation_projects first). " +
      "At least one field must be provided. A stage/status change is recorded " +
      "in the project's log history automatically. Setting status to " +
      "'completed' or 'discarded' archives the project. Only report the " +
      "update as done after this tool succeeds.",
    inputSchema: {
      type: "object",
      properties: {
        project_id: { type: "string", description: "The project's id" },
        current_stage: { type: "string", description: "New stage, e.g. 'drying', 'day 3'" },
        status: { type: "string", enum: [...FERMENTATION_STATUSES], description: "New status" },
        next_check_at: {
          type: "string",
          description: "Optional next check-in time, ISO 8601 (e.g. '2026-08-22T09:00:00Z')",
        },
        notes: { type: "string", description: "Optional note about the change" },
      },
      required: ["project_id"],
      additionalProperties: false,
    },
  },
  mutating: true,
  validate: (input) => {
    const obj = asObject(input);
    if (!obj) return { ok: false, error: "input must be an object" };
    const projectId = requireString(obj, "project_id", 100);
    if (isError(projectId)) return { ok: false, error: projectId.error };
    const currentStage = optionalString(obj, "current_stage", 100);
    if (isError(currentStage)) return { ok: false, error: currentStage.error };
    const status = optionalEnum(obj, "status", FERMENTATION_STATUSES);
    if (isError(status)) return { ok: false, error: status.error };
    const nextCheckAtRaw = obj.next_check_at;
    let nextCheckAt: string | undefined;
    if (nextCheckAtRaw !== undefined && nextCheckAtRaw !== null) {
      if (typeof nextCheckAtRaw !== "string" || Number.isNaN(Date.parse(nextCheckAtRaw))) {
        return { ok: false, error: '"next_check_at" must be a valid ISO 8601 timestamp' };
      }
      nextCheckAt = nextCheckAtRaw;
    }
    const notes = optionalString(obj, "notes", 1000);
    if (isError(notes)) return { ok: false, error: notes.error };
    if (currentStage === undefined && status === undefined && nextCheckAt === undefined) {
      return { ok: false, error: "at least one field to update must be provided" };
    }
    const value: Record<string, unknown> = { projectId };
    if (currentStage !== undefined) value.currentStage = currentStage;
    if (status !== undefined) value.status = status;
    if (nextCheckAt !== undefined) value.nextCheckAt = nextCheckAt;
    if (notes !== undefined) value.notes = notes;
    return { ok: true, value };
  },
  execute: async (ctx, input) => {
    const project = await ctx.db.updateFermentationStage(ctx.householdId, input.projectId as string, {
      currentStage: input.currentStage as string | undefined,
      status: input.status as FermentationStatus | undefined,
      nextCheckAt: input.nextCheckAt as string | undefined,
      notes: input.notes as string | undefined,
    });
    return { summary: `Updated fermentation project "${project.name}"`, data: { updated: project } };
  },
};

/** The Stream 3 registry, extended by the Household Inventory, Cleaning +
 * Home Care, and Fermentation Tracking phases. Later streams REGISTER new
 * tools here; nothing else widens agent access. */
export const toolRegistry: ReadonlyMap<string, ToolDefinition> = new Map(
  [
    getBasicHouseholdContext,
    getHouseholdPreferences,
    saveHouseholdPreference,
    getGroceryList,
    addGroceryItem,
    getInventory,
    addInventoryItem,
    updateInventoryItem,
    removeInventoryItem,
    getCleaningStatus,
    completeCleaningTask,
    skipCleaningTask,
    getFilterStatus,
    logFilterReplacement,
    getMaintenanceIssues,
    reportMaintenanceIssue,
    resolveMaintenanceIssue,
    getFermentationProjects,
    getFermentationProject,
    logFermentationEvent,
    logSourdoughFeeding,
    updateFermentationStage,
  ].map((tool) => [tool.spec.name, tool]),
);

export function toolSpecs(registry: ReadonlyMap<string, ToolDefinition>): ToolSpec[] {
  return [...registry.values()].map((tool) => tool.spec);
}
