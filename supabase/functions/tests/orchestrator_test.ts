import { assert, assertEquals, assertRejects } from "./asserts.ts";
import { runFoodieTurn } from "../_shared/orchestrator.ts";
import { FoodieError } from "../_shared/types.ts";
import { FakeDb, FakeProvider } from "./fakes.ts";

const USER = "user-1";

function turnInput(message: string, conversationId: string | null = null) {
  return { userId: USER, message, conversationId };
}

Deno.test("user without a household is rejected before any data access", async () => {
  const db = new FakeDb();
  db.membership = null;
  const provider = new FakeProvider([]);

  await assertRejects(
    () => runFoodieTurn({ db, provider }, turnInput("hi")),
    FoodieError,
    "household",
  );
  assertEquals(provider.requests.length, 0);
  assertEquals(db.actions.length, 0);
});

Deno.test("plain reply: no tools, no actions, conversation persisted", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([{ text: "Hello! I'm Foodie.", toolCalls: [] }]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("hi"));

  assertEquals(reply.text, "Hello! I'm Foodie.");
  assertEquals(reply.actions, []);
  const conversation = db.conversations.get(reply.conversationId)!;
  assertEquals(conversation.messages.map((m) => m.role), ["user", "assistant"]);
});

Deno.test("allowed tool executes, mutates, and is audited", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{ id: "t1", name: "add_grocery_item", input: { name: "Milk", quantity: 1, unit: "l" } }],
    },
    { text: "Added milk to your groceries.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("add milk"));

  assertEquals(db.groceryItems.length, 1);
  assertEquals(db.groceryItems[0].name, "Milk");
  assertEquals(reply.actions, [
    { tool: "add_grocery_item", status: "executed", summary: 'Added "Milk" to the grocery list' },
  ]);
  assertEquals(db.actions.length, 1);
  assertEquals(db.actions[0].toolName, "add_grocery_item");
  assertEquals(db.actions[0].status, "executed");
  assertEquals(db.actions[0].requestedBy, USER);
  assertEquals(db.actions[0].householdId, "hh-1");
});

Deno.test("invalid tool arguments produce a structured error and a failed audit row", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    { text: "", toolCalls: [{ id: "t1", name: "add_grocery_item", input: { quantity: 2 } }] },
    { text: "That didn't work — I couldn't add the item.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("add mystery item"));

  assertEquals(db.groceryItems.length, 0);
  assertEquals(db.actions.length, 1);
  assertEquals(db.actions[0].status, "failed");
  assert(db.actions[0].error!.includes("invalid arguments"));
  // The model was shown the failure as a structured error, not a success.
  const toolResults = provider.requests[1].messages.at(-1)!;
  assert(toolResults.role === "tool_results");
  assertEquals(toolResults.results[0].ok, false);
  // And the user-facing action list shows the failure.
  assertEquals(reply.actions[0].status, "failed");
});

Deno.test("unknown tool is refused and audited", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    { text: "", toolCalls: [{ id: "t1", name: "delete_household", input: {} }] },
    { text: "I can't do that.", toolCalls: [] },
  ]);

  await runFoodieTurn({ db, provider }, turnInput("wipe everything"));

  assertEquals(db.actions.length, 1);
  assertEquals(db.actions[0].toolName, "delete_household");
  assertEquals(db.actions[0].status, "failed");
  const toolResults = provider.requests[1].messages.at(-1)!;
  assert(toolResults.role === "tool_results");
  assertEquals(toolResults.results[0].ok, false);
});

Deno.test("model cannot invent a successful mutation: failing tool reports failure", async () => {
  const db = new FakeDb();
  db.failNextGroceryAdd = new FoodieError("internal", "the tool failed unexpectedly");
  const provider = new FakeProvider([
    { text: "", toolCalls: [{ id: "t1", name: "add_grocery_item", input: { name: "Milk" } }] },
    { text: "Done! Milk is on the list.", toolCalls: [] }, // model lies
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("add milk"));

  // Nothing was actually added, and the ACTION record — which the client
  // treats as the truth — says failed, whatever the prose claims.
  assertEquals(db.groceryItems.length, 0);
  assertEquals(reply.actions, [
    { tool: "add_grocery_item", status: "failed", summary: "Failed: the tool failed unexpectedly" },
  ]);
  assertEquals(db.actions[0].status, "failed");
});

Deno.test("no tool call at all yields an empty action list (prose alone proves nothing)", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    { text: "Added milk to your groceries!", toolCalls: [] }, // pure fabrication
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("add milk"));

  assertEquals(db.groceryItems.length, 0);
  assertEquals(reply.actions, []);
  assertEquals(db.actions.length, 0);
});

Deno.test("durable preference: save then read back through tools", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t1",
        name: "save_household_preference",
        input: { key: "grocery.shopping_day", content: "We prefer grocery shopping on Sundays." },
      }],
    },
    { text: "Saved — Sundays it is.", toolCalls: [] },
  ]);

  await runFoodieTurn({ db, provider }, turnInput("we shop on sundays, remember that"));
  assertEquals(db.memories.length, 1);
  assertEquals(db.memories[0].key, "grocery.shopping_day");

  // Next turn: the stored preference is injected into the system prompt.
  const provider2 = new FakeProvider([{ text: "You shop on Sundays.", toolCalls: [] }]);
  await runFoodieTurn({ db, provider: provider2 }, turnInput("when do we shop?"));
  assert(provider2.requests[0].system.includes("We prefer grocery shopping on Sundays."));
});

Deno.test("conversation history is storage, not memory", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([{ text: "Noted for now.", toolCalls: [] }]);

  const reply = await runFoodieTurn(
    { db, provider },
    turnInput("we prefer shopping on sundays"),
  );

  // The sentence lives in the conversation, and ONLY there — no memory was
  // created because no memory tool ran.
  assertEquals(db.memories.length, 0);
  const conversation = db.conversations.get(reply.conversationId)!;
  assert(conversation.messages.some((m) => m.content.includes("sundays")));

  // A later turn in a FRESH conversation gets no trace of it in the prompt.
  const provider2 = new FakeProvider([{ text: "No stored preference.", toolCalls: [] }]);
  await runFoodieTurn({ db, provider: provider2 }, turnInput("when do we shop?"));
  assert(!provider2.requests[0].system.includes("sundays"));
});

Deno.test("continuing a conversation includes the prior slice as history", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([{ text: "Hi Sam.", toolCalls: [] }]);
  const first = await runFoodieTurn({ db, provider }, turnInput("hello, I'm Sam"));

  const provider2 = new FakeProvider([{ text: "You said hello.", toolCalls: [] }]);
  await runFoodieTurn(
    { db, provider: provider2 },
    turnInput("what did I say before?", first.conversationId),
  );
  const sent = provider2.requests[0].messages;
  assert(sent.some((m) => m.role === "user" && m.text === "hello, I'm Sam"));
  assert(sent.some((m) => m.role === "assistant" && "text" in m && m.text === "Hi Sam."));
});

Deno.test("runaway tool loop stops at the iteration cap and says so", async () => {
  const db = new FakeDb();
  const looping = {
    text: "",
    toolCalls: [{ id: "t", name: "get_grocery_list", input: {} }],
  };
  const provider = new FakeProvider([looping, looping, looping, looping, looping]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("loop forever"));
  assertEquals(provider.requests.length, 5);
  assert(reply.text.includes("action limit"));
});

Deno.test("add_inventory_item executes, auto-creates the location, and is audited", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t1",
        name: "add_inventory_item",
        input: { name: "Milk", location: "Fridge", quantity: 1, unit: "l" },
      }],
    },
    { text: "Added milk to the fridge.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("add milk to the fridge"));

  assertEquals(db.inventoryItems.length, 1);
  assertEquals(db.inventoryItems[0].name, "Milk");
  assertEquals(db.inventoryLocations.map((l) => l.name), ["Fridge"]);
  assertEquals(reply.actions, [
    {
      tool: "add_inventory_item",
      status: "executed",
      summary: 'Added "Milk" to inventory (Fridge)',
    },
  ]);
  assertEquals(db.actions[0].status, "executed");
});

Deno.test(
  "we used the last onion: remove_inventory_item soft-deletes and is audited",
  async () => {
    const db = new FakeDb();
    db.inventoryItems.push({
      id: "inv-1",
      name: "Onion",
      locationName: "Pantry",
      quantity: null,
      unit: null,
      level: "out",
      expiresOn: null,
      openedOn: null,
      notes: null,
      deleted: false,
    });
    const provider = new FakeProvider([
      { text: "", toolCalls: [{ id: "t1", name: "remove_inventory_item", input: { item_id: "inv-1" } }] },
      { text: "Removed the onion.", toolCalls: [] },
    ]);

    const reply = await runFoodieTurn({ db, provider }, turnInput("we used the last onion"));

    assertEquals(db.inventoryItems[0].deleted, true);
    assertEquals(reply.actions, [
      { tool: "remove_inventory_item", status: "executed", summary: 'Removed "Onion" from inventory' },
    ]);
  },
);

Deno.test("update_inventory_item on an unknown id fails cleanly, nothing invented", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{ id: "t1", name: "update_inventory_item", input: { item_id: "missing", quantity: 1 } }],
    },
    { text: "Done!", toolCalls: [] }, // model lies
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("update the missing item"));

  assertEquals(reply.actions, [
    { tool: "update_inventory_item", status: "failed", summary: "Failed: inventory item not found" },
  ]);
  assertEquals(db.actions[0].status, "failed");
});

Deno.test("complete_cleaning_task executes and is audited", async () => {
  const db = new FakeDb();
  db.cleaningTasks.push({
    id: "task-1",
    name: "Clean bathroom",
    area: "Bathroom",
    rule: { intervalUnit: "week", intervalCount: 1, weekday: 0 },
    assignedUserName: null,
    suppliesNeeded: ["glass cleaner"],
    lastCompletedOn: null,
    deleted: false,
  });
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t1",
        name: "complete_cleaning_task",
        input: { task_id: "task-1", notes: "done, sparkling" },
      }],
    },
    { text: "Marked the bathroom as cleaned.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("I cleaned the bathroom"));

  assert(db.cleaningTasks[0].lastCompletedOn !== null);
  assertEquals(reply.actions, [
    { tool: "complete_cleaning_task", status: "executed", summary: 'Marked "Clean bathroom" as completed' },
  ]);
  assertEquals(db.actions[0].status, "executed");
});

Deno.test(
  "get_cleaning_status rolls an overdue Wednesday-only task to the household's cleaning days",
  async () => {
    const db = new FakeDb();
    db.cleaningTasks.push({
      id: "task-1",
      name: "Vacuum living room",
      area: "Living room",
      rule: { intervalUnit: "week", intervalCount: 1, weekday: 3 }, // Wednesday
      assignedUserName: null,
      suppliesNeeded: [],
      lastCompletedOn: "2026-07-15", // long enough ago that the theoretical due date has passed
      deleted: false,
    });
    const provider = new FakeProvider([
      { text: "", toolCalls: [{ id: "t1", name: "get_cleaning_status", input: {} }] },
      { text: "Vacuuming is overdue.", toolCalls: [] },
    ]);

    await runFoodieTurn({ db, provider }, turnInput("what needs cleaning?"));

    const toolResults = provider.requests[1].messages.at(-1)!;
    assert(toolResults.role === "tool_results");
    const payload = toolResults.results[0].payload as {
      result: { tasks: Array<{ overdue: boolean; nextDueOn: string | null }> };
    };
    const task = payload.result.tasks[0];
    // Rollover resolves the due date to today-or-later on one of the
    // household's cleaning days, so it's no longer "overdue" by the time
    // it's reported — that's the point of rolling it forward.
    assert(task.nextDueOn !== null);
    assertEquals(task.overdue, false);
    const dueDate = new Date(`${task.nextDueOn}T00:00:00Z`);
    assert(dueDate.getTime() >= new Date(new Date().toDateString()).getTime());
    assert([0, 3].includes(dueDate.getUTCDay())); // Sunday or Wednesday
  },
);

Deno.test("log_filter_replacement decrements spares and is audited", async () => {
  const db = new FakeDb();
  db.trackedComponents.push({
    id: "comp-1",
    systemName: "Kitchen fridge",
    componentName: "Water filter",
    kind: "filter",
    installedOn: "2026-01-01",
    replaceIntervalDays: 90,
    sparesCount: 1,
    lastReplacedOn: null,
    deleted: false,
  });
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t1",
        name: "log_filter_replacement",
        input: { component_id: "comp-1", notes: "new cartridge" },
      }],
    },
    { text: "Logged the filter replacement.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("I replaced the water filter"));

  assertEquals(db.trackedComponents[0].sparesCount, 0);
  assertEquals(reply.actions, [
    {
      tool: "log_filter_replacement",
      status: "executed",
      summary: 'Logged replacement of "Water filter" (Kitchen fridge)',
    },
  ]);
});

Deno.test("report then resolve a maintenance issue", async () => {
  const db = new FakeDb();
  const provider = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t1",
        name: "report_maintenance_issue",
        input: { title: "Leaky faucet", area: "Kitchen", description: "drips constantly" },
      }],
    },
    { text: "Reported the leaky faucet.", toolCalls: [] },
  ]);

  await runFoodieTurn({ db, provider }, turnInput("the kitchen faucet is leaking"));
  assertEquals(db.maintenanceIssues.length, 1);
  assertEquals(db.maintenanceIssues[0].status, "open");

  const issueId = db.maintenanceIssues[0].id;
  const provider2 = new FakeProvider([
    {
      text: "",
      toolCalls: [{
        id: "t2",
        name: "resolve_maintenance_issue",
        input: { issue_id: issueId, notes: "plumber fixed it" },
      }],
    },
    { text: "Marked the faucet issue resolved.", toolCalls: [] },
  ]);
  const reply = await runFoodieTurn({ db, provider: provider2 }, turnInput("the plumber fixed the faucet"));

  assertEquals(db.maintenanceIssues[0].status, "resolved");
  assertEquals(reply.actions, [
    {
      tool: "resolve_maintenance_issue",
      status: "executed",
      summary: 'Resolved maintenance issue "Leaky faucet"',
    },
  ]);
});

Deno.test("get_inventory is a read tool: no action entry, no audit noise in actions[]", async () => {
  const db = new FakeDb();
  db.inventoryItems.push({
    id: "inv-1",
    name: "Rice",
    locationName: null,
    quantity: 2,
    unit: "kg",
    level: null,
    expiresOn: null,
    openedOn: null,
    notes: null,
    deleted: false,
  });
  const provider = new FakeProvider([
    { text: "", toolCalls: [{ id: "t1", name: "get_inventory", input: {} }] },
    { text: "You have 2kg of rice.", toolCalls: [] },
  ]);

  const reply = await runFoodieTurn({ db, provider }, turnInput("what's in the pantry?"));

  assertEquals(reply.actions, []);
  const toolResults = provider.requests[1].messages.at(-1)!;
  assert(toolResults.role === "tool_results");
  assertEquals(toolResults.results[0].ok, true);
});
