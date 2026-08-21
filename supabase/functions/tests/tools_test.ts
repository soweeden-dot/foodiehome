import { assert, assertEquals } from "./asserts.ts";
import { toolRegistry } from "../_shared/tools.ts";

Deno.test("registry contains exactly the Stream 3 + Household Inventory + Cleaning/Home Care + Fermentation tool set", () => {
  assertEquals(
    [...toolRegistry.keys()].sort(),
    [
      "add_grocery_item",
      "add_inventory_item",
      "complete_cleaning_task",
      "get_basic_household_context",
      "get_cleaning_status",
      "get_fermentation_project",
      "get_fermentation_projects",
      "get_filter_status",
      "get_grocery_list",
      "get_household_preferences",
      "get_inventory",
      "get_maintenance_issues",
      "log_fermentation_event",
      "log_filter_replacement",
      "log_sourdough_feeding",
      "remove_inventory_item",
      "report_maintenance_issue",
      "resolve_maintenance_issue",
      "save_household_preference",
      "skip_cleaning_task",
      "update_fermentation_stage",
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
      "get_cleaning_status",
      "get_filter_status",
      "get_maintenance_issues",
      "get_fermentation_projects",
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
  assertEquals(toolRegistry.get("complete_cleaning_task")!.mutating, true);
  assertEquals(toolRegistry.get("skip_cleaning_task")!.mutating, true);
  assertEquals(toolRegistry.get("log_filter_replacement")!.mutating, true);
  assertEquals(toolRegistry.get("report_maintenance_issue")!.mutating, true);
  assertEquals(toolRegistry.get("resolve_maintenance_issue")!.mutating, true);
  assertEquals(toolRegistry.get("log_fermentation_event")!.mutating, true);
  assertEquals(toolRegistry.get("log_sourdough_feeding")!.mutating, true);
  assertEquals(toolRegistry.get("update_fermentation_stage")!.mutating, true);
  assertEquals(toolRegistry.get("get_fermentation_project")!.mutating, false);
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

Deno.test("complete_cleaning_task validation", () => {
  const tool = toolRegistry.get("complete_cleaning_task")!;

  assert(tool.validate({ task_id: "task-1" }).ok);
  assert(tool.validate({ task_id: "task-1", notes: "sparkling" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ task_id: "" }).ok);
});

Deno.test("skip_cleaning_task validation", () => {
  const tool = toolRegistry.get("skip_cleaning_task")!;

  assert(tool.validate({ task_id: "task-1" }).ok);
  assert(tool.validate({ task_id: "task-1", reason: "too tired" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ task_id: "" }).ok);
});

Deno.test("log_filter_replacement validation", () => {
  const tool = toolRegistry.get("log_filter_replacement")!;

  assert(tool.validate({ component_id: "comp-1" }).ok);
  assert(tool.validate({ component_id: "comp-1", notes: "new cartridge" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ component_id: "" }).ok);
});

Deno.test("get_maintenance_issues validation", () => {
  const tool = toolRegistry.get("get_maintenance_issues")!;

  assert(tool.validate({}).ok);
  assert(tool.validate({ status: "open" }).ok);
  assert(tool.validate({ status: "resolved" }).ok);
  assert(!tool.validate({ status: "not-a-status" }).ok);
});

Deno.test("report_maintenance_issue validation", () => {
  const tool = toolRegistry.get("report_maintenance_issue")!;

  assert(tool.validate({ title: "Leaky faucet" }).ok);
  assert(tool.validate({ title: "Leaky faucet", area: "Kitchen", description: "drips" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ title: "" }).ok);
  assert(!tool.validate({ title: "x".repeat(300) }).ok);
});

Deno.test("resolve_maintenance_issue validation", () => {
  const tool = toolRegistry.get("resolve_maintenance_issue")!;

  assert(tool.validate({ issue_id: "issue-1" }).ok);
  assert(tool.validate({ issue_id: "issue-1", notes: "plumber fixed it" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ issue_id: "" }).ok);
});

Deno.test("get_fermentation_projects validation", () => {
  const tool = toolRegistry.get("get_fermentation_projects")!;

  assert(tool.validate({}).ok);
  assert(tool.validate({ status: "active" }).ok);
  assert(tool.validate({ status: "completed" }).ok);
  assert(!tool.validate({ status: "fermenting" }).ok);
});

Deno.test("get_fermentation_project validation", () => {
  const tool = toolRegistry.get("get_fermentation_project")!;

  assert(tool.validate({ project_id: "proj-1" }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ project_id: "" }).ok);
});

Deno.test("log_fermentation_event validation", () => {
  const tool = toolRegistry.get("log_fermentation_event")!;

  assert(tool.validate({ project_id: "proj-1", log_type: "observation" }).ok);
  assert(tool.validate({
    project_id: "proj-1",
    log_type: "temperature",
    payload: { temp_c: 31 },
    notes: "warm spot",
  }).ok);
  assert(!tool.validate({}).ok); // missing project_id and log_type
  assert(!tool.validate({ project_id: "proj-1" }).ok); // missing log_type
  assert(!tool.validate({ project_id: "proj-1", log_type: "feeding" }).ok); // use log_sourdough_feeding
  assert(!tool.validate({ project_id: "proj-1", log_type: "stage_change" }).ok); // use update_fermentation_stage
  assert(!tool.validate({ project_id: "proj-1", log_type: "observation", payload: "not an object" }).ok);
  assert(!tool.validate({ project_id: "proj-1", log_type: "observation", payload: [1, 2] }).ok);
});

Deno.test("log_sourdough_feeding validation", () => {
  const tool = toolRegistry.get("log_sourdough_feeding")!;

  assert(tool.validate({ project_id: "proj-1", starter_g: 10, flour_g: 50, water_g: 50 }).ok);
  assert(tool.validate({
    project_id: "proj-1",
    starter_g: 10,
    flour_g: 50,
    water_g: 50,
    flour_type: "rye",
    discard_g: 5,
    notes: "good rise",
  }).ok);
  assert(!tool.validate({}).ok);
  assert(!tool.validate({ project_id: "proj-1", starter_g: 0, flour_g: 50, water_g: 50 }).ok);
  assert(!tool.validate({ project_id: "proj-1", starter_g: 10, flour_g: -5, water_g: 50 }).ok);
  assert(!tool.validate({ project_id: "proj-1", starter_g: 10, flour_g: 50 }).ok); // missing water_g
});

Deno.test("update_fermentation_stage validation", () => {
  const tool = toolRegistry.get("update_fermentation_stage")!;

  assert(tool.validate({ project_id: "proj-1", current_stage: "drying" }).ok);
  assert(tool.validate({ project_id: "proj-1", status: "completed" }).ok);
  assert(tool.validate({ project_id: "proj-1", next_check_at: "2026-08-22T09:00:00Z" }).ok);
  assert(!tool.validate({ project_id: "proj-1" }).ok); // no field to change
  assert(!tool.validate({ project_id: "proj-1", status: "fermenting" }).ok);
  assert(!tool.validate({ project_id: "proj-1", next_check_at: "not-a-date" }).ok);
});
