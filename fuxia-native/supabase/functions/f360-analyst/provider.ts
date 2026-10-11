// AI provider interface for the Business Analyst. The analyst only depends on AnalystModel: changing provider = a new
// implementation here (configured with F360_AI_PROVIDER / the model in f360.ai_settings), never a change to tools or audit.

export type ToolDef = { name: string; description: string; input_schema: Record<string, unknown> };
export type Block =
  | { type: 'text'; text: string }
  | { type: 'tool_use'; id: string; name: string; input: Record<string, unknown> }
  | { type: 'tool_result'; tool_use_id: string; content: string; is_error?: boolean };
export type Message = { role: 'user' | 'assistant'; content: string | Block[] };
export type Usage = { input: number; output: number; cacheRead: number; cacheWrite: number };
export type Turn = { blocks: Block[]; stop: 'tool_use' | 'end_turn' | 'max_tokens' | 'other'; usage: Usage };
export type RunParams = { system: string; messages: Message[]; tools: ToolDef[]; maxTokens: number; forceTool?: string; signal?: AbortSignal };

export interface AnalystModel {
  readonly provider: string;
  readonly model: string;
  turn(p: RunParams): Promise<Turn>;
}

type Fetch = (url: string, init: RequestInit) => Promise<Response>;

/** Anthropic Messages API (no SDK: plain fetch works in Deno and Node). System prompt and tool catalog are cached. */
export class ClaudeModel implements AnalystModel {
  readonly provider = 'anthropic';
  readonly model: string;
  private apiKey: string;
  private f: Fetch;
  constructor(model: string, apiKey: string, f: Fetch = fetch) { this.model = model; this.apiKey = apiKey; this.f = f; }
  async turn(p: RunParams): Promise<Turn> {
    const tools = p.tools.map((t, i) => (i === p.tools.length - 1 ? { ...t, cache_control: { type: 'ephemeral' } } : t));
    const res = await this.f('https://api.anthropic.com/v1/messages', {
      method: 'POST', signal: p.signal,
      headers: { 'x-api-key': this.apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: this.model, max_tokens: p.maxTokens, system: [{ type: 'text', text: p.system, cache_control: { type: 'ephemeral' } }],
        tools, messages: p.messages, ...(p.forceTool ? { tool_choice: { type: 'tool', name: p.forceTool } } : {}) }),
    });
    const j = (await res.json().catch(() => ({}))) as { content?: Block[]; stop_reason?: string; usage?: Record<string, number>; error?: { message?: string } };
    if (!res.ok) throw new Error(`Proveedor de IA respondió ${res.status}: ${(j.error?.message ?? '').slice(0, 200)}`);
    const u = j.usage ?? {};
    return { blocks: j.content ?? [], stop: (['tool_use', 'end_turn', 'max_tokens'].includes(j.stop_reason ?? '') ? j.stop_reason : 'other') as Turn['stop'],
      usage: { input: u.input_tokens ?? 0, output: u.output_tokens ?? 0, cacheRead: u.cache_read_input_tokens ?? 0, cacheWrite: u.cache_creation_input_tokens ?? 0 } };
  }
}

export function makeModel(provider: string, model: string, apiKey: string, f?: Fetch): AnalystModel {
  if (provider === 'anthropic') return new ClaudeModel(model, apiKey, f);
  throw new Error(`Proveedor de IA no soportado: ${provider}`);
}
