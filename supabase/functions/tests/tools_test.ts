import { assert, assertEquals } from "./asserts.ts";
import { toolRegistry } from "../_shared/tools.ts";

Deno.test("registry contains exactly the Stream 3 tool set", () => {
  assertEquals(
    [...toolRegistry.keys()].sort(),
    [
      "add_grocery_item",
      "get_basic_household_context",
      "get_grocery_list",
      "get_household_preferences",
      "save_household_preference",
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
  for (const name of ["get_grocery_list", "get_household_preferences", "get_basic_household_context"]) {
    const tool = toolRegistry.get(name)!;
    assert(tool.validate({}).ok);
    assert(tool.validate(undefined).ok);
    assertEquals(tool.mutating, false);
  }
});

Deno.test("mutating flags are correct", () => {
  assertEquals(toolRegistry.get("add_grocery_item")!.mutating, true);
  assertEquals(toolRegistry.get("save_household_preference")!.mutating, true);
});
