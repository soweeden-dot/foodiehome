// Anthropic implementation of the ModelProvider boundary. This file is the
// ONLY place that knows about the Anthropic wire format; swapping providers
// means adding a sibling implementation, not touching the agent.

import type {
  ModelProvider,
  ProviderMessage,
  ProviderRequest,
  ProviderTurn,
  ToolCall,
} from "./types.ts";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

type AnthropicContentBlock =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: unknown }
  | { type: "tool_result"; tool_use_id: string; content: string; is_error?: boolean };

interface AnthropicMessage {
  role: "user" | "assistant";
  content: AnthropicContentBlock[];
}

function toAnthropicMessages(messages: ProviderMessage[]): AnthropicMessage[] {
  return messages.map((message): AnthropicMessage => {
    switch (message.role) {
      case "user":
        return { role: "user", content: [{ type: "text", text: message.text }] };
      case "assistant": {
        const content: AnthropicContentBlock[] = [];
        if (message.text.trim().length > 0) {
          content.push({ type: "text", text: message.text });
        }
        for (const call of message.toolCalls) {
          content.push({ type: "tool_use", id: call.id, name: call.name, input: call.input });
        }
        return { role: "assistant", content };
      }
      case "tool_results":
        return {
          role: "user",
          content: message.results.map((result): AnthropicContentBlock => ({
            type: "tool_result",
            tool_use_id: result.toolCallId,
            content: JSON.stringify(result.payload),
            is_error: !result.ok,
          })),
        };
    }
  });
}

export class AnthropicProvider implements ModelProvider {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
  ) {
    if (!apiKey) throw new Error("AnthropicProvider requires an API key");
  }

  async generate(request: ProviderRequest): Promise<ProviderTurn> {
    const response = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": this.apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: request.maxTokens,
        system: request.system,
        messages: toAnthropicMessages(request.messages),
        tools: request.tools.map((tool) => ({
          name: tool.name,
          description: tool.description,
          input_schema: tool.inputSchema,
        })),
      }),
    });

    if (!response.ok) {
      // Log details server-side; propagate a generic error (no key material,
      // no request payload) so nothing sensitive can reach the client.
      const detail = await response.text();
      console.error(`Anthropic API error ${response.status}: ${detail.slice(0, 500)}`);
      throw new Error(`model provider request failed (${response.status})`);
    }

    const body = await response.json() as { content: AnthropicContentBlock[] };
    let text = "";
    const toolCalls: ToolCall[] = [];
    for (const block of body.content ?? []) {
      if (block.type === "text") text += block.text;
      if (block.type === "tool_use") {
        toolCalls.push({ id: block.id, name: block.name, input: block.input });
      }
    }
    return { text, toolCalls };
  }
}
