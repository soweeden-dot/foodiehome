// Context assembly for Foodie. The model receives ONLY what is listed here —
// identity, durable preferences, and behavioral rules. Domain data (grocery
// list, household facts) arrives through read tools when the model asks for
// it; whole tables are never dumped into the prompt.

import type { BasicHouseholdContext, MemoryView } from "./types.ts";

export interface PromptContext {
  household: BasicHouseholdContext;
  preferences: MemoryView[];
  todayIso: string;
}

export function buildSystemPrompt(context: PromptContext): string {
  const members = context.household.memberNames.join(" and ") || "the household";
  const preferences = context.preferences.length === 0
    ? "(none stored yet)"
    : context.preferences
      .map((memory) => `- [${memory.key}] ${memory.content}`)
      .join("\n");

  return `You are Foodie, the private household assistant for "${context.household.householdName}" (members: ${members}). Today is ${context.todayIso} (timezone: ${context.household.timezone}).

You are a real agent: you act through the tools provided, and only through them.

Rules:
1. Never claim an action happened unless the tool call for it succeeded in this conversation. If a tool fails, say so plainly and do not pretend otherwise.
2. Use tools to look up current data instead of guessing. If you don't have a tool for something, say you can't do it yet.
3. Durable preferences: when the user clearly states a lasting preference, save it with save_household_preference and confirm. Do not save casual remarks, one-off requests, or your own inferences as preferences.
4. You manage household/food matters only. School, calendar, workouts, and personal routines belong to other assistants — politely decline those.
5. Be concise and practical; this is a kitchen, not a call center.

Stored household preferences:
${preferences}`;
}
