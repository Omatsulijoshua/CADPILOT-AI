import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { PrismaService } from './prisma.service';

const commandSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'commandId', 'intent', 'target', 'operations', 'assumptions', 'requiresConfirmation'],
  properties: {
    schemaVersion: { type: 'integer', const: 1 },
    commandId: { type: 'string' },
    intent: { type: 'string', enum: ['create_model', 'modify_model'] },
    target: { type: 'object', additionalProperties: false, required: ['type', 'ids'], properties: { type: { type: 'string', enum: ['model', 'selection', 'sketch'] }, ids: { type: 'array', items: { type: 'string' } } } },
    operations: { type: 'array', minItems: 1, maxItems: 12, items: { type: 'object', additionalProperties: false, required: ['operationId', 'type', 'parameters'], properties: {
      operationId: { type: 'string' }, type: { type: 'string', enum: ['extrude', 'cut', 'rename', 'delete'] },
      parameters: { type: 'object', additionalProperties: false, properties: { profileId: { type: ['string', 'null'] }, depth: { type: ['number', 'null'] }, operationId: { type: ['string', 'null'] }, name: { type: ['string', 'null'] } }, required: ['profileId', 'depth', 'operationId', 'name'] }
    } } },
    assumptions: { type: 'array', items: { type: 'string' }, maxItems: 12 },
    requiresConfirmation: { type: 'boolean', const: true }
  }
} as const;

const defaultTimeoutMs = 30_000;
const minTimeoutMs = 1_000;
const maxTimeoutMs = 120_000;

type JsonRecord = Record<string, unknown>;
type ResponseUsage = { input_tokens?: unknown; output_tokens?: unknown; total_tokens?: unknown };
type OpenAiResponse = { id?: unknown; output?: unknown; usage?: ResponseUsage };

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function tokenCount(value: unknown): number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function timeoutMs(value: string | undefined): number {
  if (value == null || value.trim() === '') return defaultTimeoutMs;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= minTimeoutMs && parsed <= maxTimeoutMs
    ? parsed
    : defaultTimeoutMs;
}

function outputText(result: OpenAiResponse): string | null {
  if (!Array.isArray(result.output)) return null;
  for (const item of result.output) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue;
    for (const content of item.content) {
      if (isRecord(content) && content.type === 'output_text' && typeof content.text === 'string' && content.text.trim() !== '') {
        return content.text;
      }
    }
  }
  return null;
}

function validCommand(value: unknown): value is JsonRecord {
  if (!isRecord(value) || value.schemaVersion !== 1 || typeof value.commandId !== 'string' || value.commandId.trim() === '') return false;
  if (value.intent !== 'create_model' && value.intent !== 'modify_model') return false;
  if (!isRecord(value.target) || !['model', 'selection', 'sketch'].includes(String(value.target.type)) || !Array.isArray(value.target.ids)) return false;
  if (!value.target.ids.every(id => typeof id === 'string' && id.trim() !== '')) return false;
  if (!Array.isArray(value.operations) || value.operations.length < 1 || value.operations.length > 12) return false;
  if (!value.operations.every(operation => isRecord(operation)
    && typeof operation.operationId === 'string'
    && operation.operationId.trim() !== ''
    && ['extrude', 'cut', 'rename', 'delete'].includes(String(operation.type))
    && isRecord(operation.parameters))) return false;
  if (!Array.isArray(value.assumptions) || value.assumptions.length > 12 || !value.assumptions.every(item => typeof item === 'string')) return false;
  return value.requiresConfirmation === true;
}

@Injectable()
export class AiService {
  constructor(private readonly prisma: PrismaService) {}

  async generateCommand(userId: string, prompt: string, context: object) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new ServiceUnavailableException('AI commands are not configured on this server');
    const model = process.env.OPENAI_CAD_MODEL ?? 'gpt-5.6-luna';
    let response: Response;
    try {
      response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          model,
          store: false,
          instructions: 'Convert the user request into a safe CadPilot command. Use only IDs present in context. Never invent geometry IDs. All dimensions are millimetres. Return requiresConfirmation=true.',
          input: JSON.stringify({ prompt, context }),
          text: { format: { type: 'json_schema', name: 'cadpilot_command', strict: true, schema: commandSchema } }
        }),
        signal: AbortSignal.timeout(timeoutMs(process.env.OPENAI_TIMEOUT_MS)),
      });
    } catch {
      throw new ServiceUnavailableException('AI command generation is temporarily unavailable');
    }
    if (!response.ok) throw new ServiceUnavailableException('AI command generation is temporarily unavailable');

    let decoded: unknown;
    try {
      decoded = await response.json();
    } catch {
      throw new ServiceUnavailableException('AI returned an invalid response');
    }
    if (!isRecord(decoded)) throw new ServiceUnavailableException('AI returned an invalid response');
    const result = decoded as OpenAiResponse;
    const usage = {
      inputTokens: tokenCount(result.usage?.input_tokens),
      outputTokens: tokenCount(result.usage?.output_tokens),
      totalTokens: tokenCount(result.usage?.total_tokens),
    };
    await this.prisma.aiUsage.create({ data: {
      userId,
      provider: 'openai',
      model,
      responseId: typeof result.id === 'string' ? result.id : undefined,
      ...usage,
    }});

    const text = outputText(result);
    if (!text) throw new ServiceUnavailableException('AI returned no structured command');
    let command: unknown;
    try {
      command = JSON.parse(text);
    } catch {
      throw new ServiceUnavailableException('AI returned an invalid structured command');
    }
    if (!validCommand(command)) throw new ServiceUnavailableException('AI returned an invalid structured command');
    return { command, usage };
  }
}
