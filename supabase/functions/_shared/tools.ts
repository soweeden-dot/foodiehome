// Foodie's tool registry — the ONLY capabilities the model has. Each tool
// validates its input, is executed against the narrow FoodieDb interface
// (user-JWT + RLS underneath), and reports a human-readable summary that
// feeds the intent-level audit (agent_actions).
//
// Stream 3 set (deliberately small):
//   get_basic_household_context, get_household_preferences,
//   save_household_preference, get_grocery_list, add_grocery_item
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

/** The Stream 3 registry. Later streams add tools; nothing else does. */
export const toolRegistry: ReadonlyMap<string, ToolDefinition> = new Map(
  [
    getBasicHouseholdContext,
    getHouseholdPreferences,
    saveHouseholdPreference,
    getGroceryList,
    addGroceryItem,
  ].map((tool) => [tool.spec.name, tool]),
);

export function toolSpecs(registry: ReadonlyMap<string, ToolDefinition>): ToolSpec[] {
  return [...registry.values()].map((tool) => tool.spec);
}
