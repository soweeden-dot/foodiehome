import { assert, assertEquals } from "./asserts.ts";
import { createHandler, type AuthedUser } from "../_shared/handler.ts";
import { FakeDb, FakeProvider } from "./fakes.ts";

function makeHandler(options: {
  user?: AuthedUser | null;
  db?: FakeDb;
  provider?: FakeProvider;
}) {
  const db = options.db ?? new FakeDb();
  const provider = options.provider ??
    new FakeProvider([{ text: "Hello!", toolCalls: [] }]);
  const handler = createHandler({
    authenticate: () => Promise.resolve(options.user ?? null),
    createDb: () => db,
    provider,
  });
  return { handler, db, provider };
}

function post(body: unknown): Request {
  return new Request("http://localhost/foodie-agent", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("unauthenticated request is rejected with 401 and touches nothing", async () => {
  const { handler, db, provider } = makeHandler({ user: null });
  const response = await handler(post({ message: "hi" }));
  assertEquals(response.status, 401);
  const body = await response.json();
  assertEquals(body.error.code, "unauthenticated");
  assertEquals(provider.requests.length, 0);
  assertEquals(db.actions.length, 0);
});

Deno.test("authenticated user without a household gets 403", async () => {
  const db = new FakeDb();
  db.membership = null;
  const { handler } = makeHandler({ user: { userId: "u1", token: "t" }, db });
  const response = await handler(post({ message: "hi" }));
  assertEquals(response.status, 403);
  const body = await response.json();
  assertEquals(body.error.code, "no_household");
});

Deno.test("valid request returns the reply with conversation id", async () => {
  const { handler } = makeHandler({ user: { userId: "u1", token: "t" } });
  const response = await handler(post({ message: "hi" }));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.text, "Hello!");
  assert(typeof body.conversationId === "string");
  assertEquals(body.actions, []);
});

Deno.test("missing or oversized message is a structured 400", async () => {
  const { handler } = makeHandler({ user: { userId: "u1", token: "t" } });

  const empty = await handler(post({ message: "   " }));
  assertEquals(empty.status, 400);
  assertEquals((await empty.json()).error.code, "invalid_argument");

  const huge = await handler(post({ message: "x".repeat(5000) }));
  assertEquals(huge.status, 400);

  const notJson = await handler(
    new Request("http://localhost/foodie-agent", { method: "POST", body: "nope" }),
  );
  assertEquals(notJson.status, 400);
});

Deno.test("internal failures return a generic error, never raw details", async () => {
  const provider = new FakeProvider([]); // will throw: out of scripted turns
  const { handler } = makeHandler({ user: { userId: "u1", token: "t" }, provider });
  const response = await handler(post({ message: "hi" }));
  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.error.code, "internal");
  assert(!JSON.stringify(body).includes("scripted"));
});

Deno.test("only POST is served", async () => {
  const { handler } = makeHandler({ user: { userId: "u1", token: "t" } });
  const response = await handler(
    new Request("http://localhost/foodie-agent", { method: "GET" }),
  );
  assertEquals(response.status, 405);
});
