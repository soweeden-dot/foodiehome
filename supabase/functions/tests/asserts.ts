// Minimal assertion helpers (vendored — this environment cannot always reach
// jsr.io, and the dependency philosophy says a page of code beats a fetch).

export class AssertionError extends Error {}

export function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new AssertionError(message);
}

export function assertEquals(actual: unknown, expected: unknown, message?: string): void {
  const a = JSON.stringify(sortKeys(actual));
  const b = JSON.stringify(sortKeys(expected));
  if (a !== b) {
    throw new AssertionError(message ?? `expected ${b}, got ${a}`);
  }
}

export async function assertRejects(
  fn: () => Promise<unknown>,
  // deno-lint-ignore no-explicit-any
  errorClass?: new (...args: any[]) => Error,
  messageIncludes?: string,
): Promise<void> {
  try {
    await fn();
  } catch (error) {
    if (errorClass && !(error instanceof errorClass)) {
      throw new AssertionError(
        `expected ${errorClass.name}, got ${(error as Error).constructor.name}`,
      );
    }
    if (messageIncludes && !(error as Error).message.includes(messageIncludes)) {
      throw new AssertionError(
        `expected message to include "${messageIncludes}", got "${(error as Error).message}"`,
      );
    }
    return;
  }
  throw new AssertionError("expected the promise to reject, but it resolved");
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([x], [y]) => x.localeCompare(y))
        .map(([k, v]) => [k, sortKeys(v)]),
    );
  }
  return value;
}
