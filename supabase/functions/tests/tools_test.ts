import { assert, assertEquals } from "./asserts.ts";
import { toolRegistry } from "../_shared/tools.ts";

Deno.test("registry contains exactly the Stream 3 + Household Inventory tool set", () => {
  assertEquals(
    [...toolRegistry.keys()].sort(),
    [
      "add_grocery_item",
      "add_inventory_item",
      "get_basic_household_context",
      "get_grocery_list",
      "get_household_preferences",
      "get_inventory",
      "remove_inventory_item",
      "save_household_preference",
      "update_inventory_item",
    ],
  );
});

Deno.test("add_grocery_item validation", () => {
  const tool = toolRegistry.get("add_grocery_item")!;

  assert(tool.validate({ name: "Milk" }).ok);
  assert(tool.validate({ name: "Milk", quantity: 2, unit: "l", notes: "oat" }).ok);

  assert(!tool.validate(null).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ name: "" }).ok);
  assert(!tool.validate({ name: 42 }).ok);
  assert(!tool.validate({ name: "Milk", quantity: -1 }).ok);
  assert(!tool.validate({ name: "Milk", quantity: Number.NaN }).ok);
  assert(!tool.validate({ name: "x".repeat(300) }).ok);

  // Whitespace-only optionals are dropped, not stored as empty strings.
  const validated = tool.validate({ name: " Milk ", unit: "  " });
  assert(validated.ok);
  assertEquals(validated.value, { name: "Milk" });
});

Deno.test("save_household_preference validation", () => {
  const tool = toolRegistry.get("save_household_preference")!;

  assert(tool.validate({ key: "grocery.shopping_day", content: "Sundays." }).ok);
  assert(!tool.validate({ key: "", content: "x" }).ok);
  assert(!tool.validate({ key: "k" }).ok);
  assert(!tool.validate({ content: "x" }).ok);
  assert(!tool.validate({ key: "k", content: "y".repeat(3000) }).ok);
});

Deno.test("read tools accept empty input", () => {
  for (
    const name of [
      "get_grocery_list",
      "get_household_preferences",
      "get_basic_household_context",
      "get_inventory",
    ]
  ) {
    const tool = toolRegistry.get(name)!;
    assert(tool.validate({}).ok);
    assert(tool.validate(undefined).ok);
    assertEquals(tool.mutating, false);
  }
});

Deno.test("mutating flags are correct", () => {
  assertEquals(toolRegistry.get("add_grocery_item")!.mutating, true);
  assertEquals(toolRegistry.get("save_household_preference")!.mutating, true);
  assertEquals(toolRegistry.get("add_inventory_item")!.mutating, true);
  assertEquals(toolRegistry.get("update_inventory_item")!.mutating, true);
  assertEquals(toolRegistry.get("remove_inventory_item")!.mutating, true);
});

Deno.test("add_inventory_item validation", () => {
  const tool = toolRegistry.get("add_inventory_item")!;

  assert(tool.validate({ name: "Milk" }).ok);
  assert(
    tool.validate({
      name: "Milk",
      location: "Fridge",
      quantity: 1,
      unit: "l",
      level: "good",
      expires_on: "2026-09-01",
      notes: "organic",
    }).ok,
  );

  assert(!tool.validate(null).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ name: "" }).ok);
  assert(!tool.validate({ name: "Milk", quantity: -1 }).ok);
  assert(!tool.validate({ name: "Milk", level: "spoiled" }).ok); // not in the enum
  assert(!tool.validate({ name: "Milk", expires_on: "not-a-date" }).ok);
  assert(!tool.validate({ name: "Milk", expires_on: "2026-13-40" }).ok); // invalid calendar date
  assert(!tool.validate({ name: "Milk", location: "x".repeat(200) }).ok);
});

Deno.test("update_inventory_item validation", () => {
  const tool = toolRegistry.get("update_inventory_item")!;

  assert(tool.validate({ item_id: "inv-1", quantity: 2 }).ok);
  assert(tool.validate({ item_id: "inv-1", level: "low" }).ok);
  assert(tool.validate({ item_id: "inv-1", opened_on: "2026-08-01" }).ok);

  assert(!tool.validate({}).ok); // missing item_id
  assert(!tool.validate({ item_id: "inv-1" }).ok); // no field to change
  assert(!tool.validate({ item_id: "inv-1", level: "bad-level" }).ok);
  assert(!tool.validate({ item_id: "inv-1", quantity: -5 }).ok);
});

Deno.test("remove_inventory_item validation", () => {
  const tool = toolRegistry.get("remove_inventory_item")!;

  assert(tool.validate({ item_id: "inv-1" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ item_id: "" }).ok);
});
