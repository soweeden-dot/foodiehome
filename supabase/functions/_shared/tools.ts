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
// Later streams REGISTER new tools here; nothing else widens agent access.

import type { FoodieDb, ToolSpec } from "./types.ts";

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

/** The Stream 3 registry, extended by the Household Inventory phase. Later
 * streams REGISTER new tools here; nothing else widens agent access. */
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
  ].map((tool) => [tool.spec.name, tool]),
);

export function toolSpecs(registry: ReadonlyMap<string, ToolDefinition>): ToolSpec[] {
  return [...registry.values()].map((tool) => tool.spec);
}
