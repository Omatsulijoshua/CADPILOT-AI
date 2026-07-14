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

type ResponseUsage = { input_tokens?: number; output_tokens?: number; total_tokens?: number };
type OpenAiResponse = { id?: string; output?: Array<{ content?: Array<{ type?: string; text?: string }> }>; usage?: ResponseUsage };

@Injectable()
export class AiService {
  constructor(private readonly prisma: PrismaService) {}

  async generateCommand(userId: string, prompt: string, context: object) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new ServiceUnavailableException('AI commands are not configured on this server');
    const model = process.env.OPENAI_CAD_MODEL ?? 'gpt-5.6-luna';
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        model,
        store: false,
        instructions: 'Convert the user request into a safe CadPilot command. Use only IDs present in context. Never invent geometry IDs. All dimensions are millimetres. Return requiresConfirmation=true.',
        input: JSON.stringify({ prompt, context }),
        text: { format: { type: 'json_schema', name: 'cadpilot_command', strict: true, schema: commandSchema } }
      })
    });
    if (!response.ok) throw new ServiceUnavailableException('AI command generation is temporarily unavailable');
    const result = await response.json() as OpenAiResponse;
    const text = result.output?.flatMap(item => item.content ?? []).find(item => item.type === 'output_text')?.text;
    if (!text) throw new ServiceUnavailableException('AI returned no structured command');
    const command = JSON.parse(text) as object;
    const usage = result.usage ?? {};
    await this.prisma.aiUsage.create({ data: {
      userId, provider: 'openai', model, responseId: result.id,
      inputTokens: usage.input_tokens ?? 0, outputTokens: usage.output_tokens ?? 0,
      totalTokens: usage.total_tokens ?? 0,
    }});
    return { command, usage: { inputTokens: usage.input_tokens ?? 0, outputTokens: usage.output_tokens ?? 0, totalTokens: usage.total_tokens ?? 0 } };
  }
}