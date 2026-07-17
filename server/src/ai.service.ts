import { BadRequestException, Injectable, PayloadTooLargeException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { PrismaService } from './prisma.service';
import { AiKeyVaultService } from './ai-key-vault.service';

const commandSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'commandId', 'intent', 'target', 'operations', 'assumptions', 'requiresConfirmation'],
  properties: {
    schemaVersion: { type: 'integer', const: 1 },
    commandId: { type: 'string' },
    intent: { type: 'string', enum: ['create_model', 'modify_model'] },
    target: { type: 'object', additionalProperties: false, required: ['type', 'ids'], properties: { type: { type: 'string', enum: ['model', 'selection', 'sketch'] }, ids: { type: 'array', items: { type: 'string' } } } },
    operations: { type: 'array', minItems: 1, maxItems: 12, items: { type: 'object', additionalProperties: false, required: ['operationId', 'type', 'parameters'], properties: {
      operationId: { type: 'string' }, type: { type: 'string', enum: ['extrude', 'cut', 'revolve', 'gear', 'shell', 'fillet', 'chamfer', 'rename', 'delete'] },
      parameters: { type: 'object', additionalProperties: false, properties: { profileId: { type: ['string', 'null'] }, depth: { type: ['number', 'null'] }, angle: { type: ['number', 'null'] }, teeth: { type: ['number', 'null'] }, boreRadius: { type: ['number', 'null'] }, thickness: { type: ['number', 'null'] }, radius: { type: ['number', 'null'] }, distance: { type: ['number', 'null'] }, operationId: { type: ['string', 'null'] }, name: { type: ['string', 'null'] } }, required: ['profileId', 'depth', 'angle', 'teeth', 'boreRadius', 'thickness', 'radius', 'distance', 'operationId', 'name'] }
    } } },
    assumptions: { type: 'array', items: { type: 'string' }, maxItems: 12 },
    requiresConfirmation: { type: 'boolean', const: true }
  }
} as const;

const defaultTimeoutMs = 30_000;
const minTimeoutMs = 1_000;
const maxTimeoutMs = 120_000;
const maxPromptLength = 2_000;
const maxInputBytes = 64 * 1024;

type JsonRecord = Record<string, unknown>;
type ResponseUsage = { input_tokens?: unknown; output_tokens?: unknown; total_tokens?: unknown };
type OpenAiResponse = { id?: unknown; output?: unknown; usage?: ResponseUsage };
type ChatResponse = { id?: unknown; choices?: unknown; usage?: ResponseUsage };
type UsageRecordData = {
  userId: string;
  projectId?: string;
  provider: string;
  model: string;
  responseId?: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
};

export type CadPlan = {
  schemaVersion: 1;
  planId: string;
  summary: string;
  extracted: { objectType: string; style: string | null; dimensions: Array<{ name: string; value: number | null; unit: 'mm' }>; constraints: string[] };
  missingInputs: Array<{ id: string; label: string; question: string; required: boolean; suggestedValue: string }>;
  options: Array<{ id: string; title: string; description: string; stages: string[]; assumptions: string[]; executableNow: boolean; preparation: string[] }>;
  canUseDefaults: boolean;
};

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

function monthlyTokenLimit(): number | null {
  const value = process.env.AI_MONTHLY_TOKEN_LIMIT;
  if (value == null || value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
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

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim() !== '';
}

function positiveNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}

function wholeNumberBetween(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max;
}

function validParameters(type: string, parameters: JsonRecord): boolean {
  switch (type) {
    case 'extrude':
    case 'cut':
      return nonEmptyString(parameters.profileId) && positiveNumber(parameters.depth);
    case 'revolve':
      return nonEmptyString(parameters.profileId) && parameters.angle === 360;
    case 'gear':
      return nonEmptyString(parameters.profileId) && positiveNumber(parameters.depth) && wholeNumberBetween(parameters.teeth, 6, 80) && (parameters.boreRadius == null || (typeof parameters.boreRadius === 'number' && Number.isFinite(parameters.boreRadius) && parameters.boreRadius >= 0));
    case 'shell':
      return positiveNumber(parameters.thickness);
    case 'fillet':
      return positiveNumber(parameters.radius);
    case 'chamfer':
      return positiveNumber(parameters.distance);
    case 'rename':
      return nonEmptyString(parameters.operationId) && nonEmptyString(parameters.name);
    case 'delete':
      return nonEmptyString(parameters.operationId);
    default:
      return false;
  }
}

function commandInput(prompt: string, context: object): string {
  if (typeof prompt !== 'string' || prompt.trim() === '' || prompt.length > maxPromptLength) {
    throw new BadRequestException('AI prompt must contain between 1 and 2000 characters');
  }

  let input: string;
  try {
    input = JSON.stringify({ prompt, context });
  } catch {
    throw new BadRequestException('AI command context must be JSON serializable');
  }
  if (new TextEncoder().encode(input).byteLength > maxInputBytes) {
    throw new PayloadTooLargeException('AI command context is too large');
  }
  return input;
}

function commandSystemPrompt(): string {
  return [
    'You are CadPilot\'s CAD command converter.',
    'Return JSON only. It must match this JSON schema exactly:',
    JSON.stringify(commandSchema),
    'Use only supported operation types: extrude, cut, revolve, gear, shell, fillet, chamfer, rename, delete.',
    'Use gear only with an existing circular profileId; set teeth between 6 and 80 and boreRadius to 0 or a safe smaller radius.',
    'Every operation.parameters object must include all keys from the schema. Use null for unused parameter fields.',
    'Use only geometry IDs that already exist in the supplied context. Do not invent profile, sketch, model, or operation IDs from outside the context.',
    'For broad or multi-stage plans, generate only the next currently executable CAD stage from the selected plan.',
    'All dimensions are millimetres. requiresConfirmation must be true.',
  ].join(' ');
}

function validCommand(value: unknown): value is JsonRecord {
  if (!isRecord(value) || value.schemaVersion !== 1 || typeof value.commandId !== 'string' || value.commandId.trim() === '') return false;
  if (value.intent !== 'create_model' && value.intent !== 'modify_model') return false;
  if (!isRecord(value.target) || !['model', 'selection', 'sketch'].includes(String(value.target.type)) || !Array.isArray(value.target.ids)) return false;
  if (!value.target.ids.every(id => typeof id === 'string' && id.trim() !== '')) return false;
  if (new Set(value.target.ids).size !== value.target.ids.length) return false;
  if (!Array.isArray(value.operations) || value.operations.length < 1 || value.operations.length > 12) return false;
  if (!value.operations.every(operation => isRecord(operation)
    && nonEmptyString(operation.operationId)
    && typeof operation.type === 'string'
    && isRecord(operation.parameters)
    && validParameters(operation.type, operation.parameters))) return false;
  if (new Set(value.operations.map(operation => (operation as JsonRecord).operationId)).size !== value.operations.length) return false;
  if (!Array.isArray(value.assumptions) || value.assumptions.length > 12 || !value.assumptions.every(item => typeof item === 'string')) return false;
  return value.requiresConfirmation === true;
}

function existingOperationIds(context: object): Set<string> {
  const ids = new Set<string>();
  if (!isRecord(context) || !isRecord(context.model) || !Array.isArray(context.model.operations)) return ids;
  for (const operation of context.model.operations) {
    if (isRecord(operation) && nonEmptyString(operation.id)) ids.add(operation.id);
  }
  return ids;
}

function uniqueCommandOperationIds(command: unknown, context: object): unknown {
  if (!isRecord(command) || !Array.isArray(command.operations)) return command;
  const used = existingOperationIds(context);
  const next = { ...command, operations: command.operations.map(operation => {
    if (!isRecord(operation)) return operation;
    let operationId = nonEmptyString(operation.operationId) ? operation.operationId : '';
    if (operationId === '' || used.has(operationId)) {
      do { operationId = randomUUID(); } while (used.has(operationId));
    }
    used.add(operationId);
    return { ...operation, operationId };
  }) };
  return next;
}

function validStringArray(value: unknown, min = 0, max = 12): value is string[] {
  return Array.isArray(value) && value.length >= min && value.length <= max && value.every(nonEmptyString);
}

function validPlan(value: unknown): value is CadPlan {
  if (!isRecord(value) || value.schemaVersion !== 1 || !nonEmptyString(value.planId) || !nonEmptyString(value.summary)) return false;
  if (!isRecord(value.extracted) || !nonEmptyString(value.extracted.objectType) || !Array.isArray(value.extracted.dimensions) || !validStringArray(value.extracted.constraints)) return false;
  if (!value.extracted.dimensions.every(item => isRecord(item) && nonEmptyString(item.name) && (item.value === null || positiveNumber(item.value)) && item.unit === 'mm')) return false;
  if (!Array.isArray(value.missingInputs) || value.missingInputs.length > 8 || !value.missingInputs.every(item => isRecord(item) && nonEmptyString(item.id) && nonEmptyString(item.label) && nonEmptyString(item.question) && typeof item.required === 'boolean' && typeof item.suggestedValue === 'string')) return false;
  if (!Array.isArray(value.options) || value.options.length < 2 || value.options.length > 3) return false;
  if (!value.options.every(option => isRecord(option) && nonEmptyString(option.id) && nonEmptyString(option.title) && nonEmptyString(option.description) && validStringArray(option.stages, 2, 12) && validStringArray(option.assumptions) && typeof option.executableNow === 'boolean' && validStringArray(option.preparation))) return false;
  return typeof value.canUseDefaults === 'boolean';
}

function localPlan(prompt: string, context: object): CadPlan {
  const lower = prompt.toLowerCase();
  const table = lower.includes('table') || lower.includes('desk');
  const chair = lower.includes('chair') || lower.includes('seat');
  const gear = lower.includes('gear') || lower.includes('sprocket');
  const boredRound = lower.includes('pipe') || lower.includes('tube') || lower.includes('wheel') || lower.includes('pulley') || lower.includes('bearing');
  const round = boredRound || lower.includes('cylinder') || lower.includes('shaft') || lower.includes('rod') || lower.includes('disc') || lower.includes('disk') || lower.includes('round');
  const hasProfile = JSON.stringify(context).includes('rectangle');
  const dimensions = table
    ? [{ name: 'width', value: null, unit: 'mm' as const }, { name: 'depth', value: null, unit: 'mm' as const }, { name: 'height', value: null, unit: 'mm' as const }, { name: 'top thickness', value: null, unit: 'mm' as const }]
    : round || gear
      ? [{ name: 'diameter', value: null, unit: 'mm' as const }, { name: 'thickness', value: null, unit: 'mm' as const }, ...(gear ? [{ name: 'teeth', value: null, unit: 'mm' as const }] : [])]
    : [{ name: 'primary size', value: null, unit: 'mm' as const }];
  const missingInputs = table
    ? [
        { id: 'width', label: 'Width', question: 'How wide should it be?', required: true, suggestedValue: '1200 mm' },
        { id: 'depth', label: 'Depth', question: 'How deep should it be?', required: true, suggestedValue: '600 mm' },
        { id: 'height', label: 'Height', question: 'How tall should it be?', required: true, suggestedValue: '750 mm' },
        { id: 'topThickness', label: 'Top thickness', question: 'How thick should the tabletop be?', required: false, suggestedValue: '30 mm' },
        { id: 'legStyle', label: 'Leg style', question: 'Which leg style do you prefer?', required: false, suggestedValue: 'Four square legs' },
      ]
    : gear
      ? [
          { id: 'diameter', label: 'Gear diameter', question: 'What outside diameter should the gear use?', required: true, suggestedValue: '300 mm' },
          { id: 'thickness', label: 'Gear thickness', question: 'How thick should the gear be?', required: false, suggestedValue: '18 mm' },
          { id: 'teeth', label: 'Teeth', question: 'How many teeth should it have?', required: false, suggestedValue: '18' },
          { id: 'boreRadius', label: 'Bore radius', question: 'What center bore radius should it use?', required: false, suggestedValue: '35 mm' },
        ]
    : round
      ? [
          { id: 'diameter', label: 'Diameter', question: 'What outside diameter should it use?', required: true, suggestedValue: '120 mm' },
          { id: 'length', label: boredRound ? 'Thickness / length' : 'Length', question: 'How long or thick should it be?', required: true, suggestedValue: boredRound ? '30 mm' : '100 mm' },
          ...(boredRound ? [{ id: 'boreRadius', label: 'Bore radius', question: 'What center bore radius should it use?', required: false, suggestedValue: '20 mm' }] : []),
        ]
    : [{ id: 'size', label: 'Main dimension', question: 'What primary size should CadPilot use?', required: true, suggestedValue: '100 mm' }];
  const commonStages = ['Confirm dimensions and constraints', 'Generate sketches and closed profiles', 'Create primary solids', 'Add secondary features and joins', 'Validate dimensions', 'Show preview for approval'];
  const tableOptions = [
    ['rectangular-four-leg', 'Rectangular tabletop with four legs', 'A practical general-purpose table with a rectangular top and four square legs.'],
    ['round-pedestal', 'Round tabletop with pedestal base', 'A circular table with a centred pedestal and stabilising base.'],
    ['desk-drawers', 'Desk-style table with drawers', 'A rectangular work desk with a drawer unit and leg structure.'],
  ];
  const roundOptions = [
    ['revolved-solid', boredRound ? 'Round part with center bore' : 'Revolved round solid', boredRound ? 'Create a wheel, pulley, tube, or bearing-like starter with a centered bore.' : 'Create a cylinder, shaft, rod, or disc as an editable revolved solid.'],
    ['lightened-round', 'Lightweight round part', 'Start with a round body and add holes or cutouts in later stages.'],
    ['parametric-round', 'Parametric rotational part', 'Keep the round profile dimensions editable for later detail work.'],
  ];
  const gearOptions = [
    ['toothed-gear', 'Toothed gear with center bore', 'Create a toothed gear starter from a circular profile.'],
    ['gear-train-starter', 'Gear train starter', 'Create one gear first, then add mating gears in the next stage.'],
    ['sprocket-style', 'Sprocket-style gear', 'Create a toothed wheel prepared for later chain or linkage details.'],
  ];
  const furnitureOptions = [
    ['furniture-starter', 'Furniture starter assembly', 'Create separate starter solids for the main furniture parts.'],
    ['minimal-furniture', 'Minimal clean furniture', 'Use simple editable solids and add details later.'],
    ['detailed-furniture', 'Detailed staged furniture', 'Plan joins, legs, supports, and storage as staged features.'],
  ];
  const genericOptions = [
    ['simple-solid', 'Simple solid starting point', 'Build the smallest manufacturable interpretation first.'],
    ['lightweight', 'Lightweight or hollow design', 'Reduce material while preserving the main form.'],
    ['parametric', 'Parametric detailed design', 'Use editable dimensions and staged secondary features.'],
  ];
  const options = gear ? gearOptions : round ? roundOptions : table ? tableOptions : chair ? furnitureOptions : genericOptions;
  const objectType = gear ? 'gear' : round ? (boredRound ? 'bored round part' : 'round part') : table ? 'table' : chair ? 'furniture' : 'custom CAD part';
  return {
    schemaVersion: 1,
    planId: `local-${Date.now()}`,
    summary: table ? 'I can create this as a table design. Choose a construction approach and confirm the essential dimensions.' : `I extracted a buildable CAD path for: ${prompt.trim()}`,
    extracted: { objectType, style: lower.includes('modern') ? 'modern' : null, dimensions, constraints: [] },
    missingInputs,
    options: options.map(([id, title, description], index) => ({ id, title, description, stages: commonStages, assumptions: ['Dimensions are millimetres.', 'The final model requires preview approval.'], executableNow: hasProfile && index === 0, preparation: hasProfile ? [] : ['Create or select the required closed sketch profiles before geometry generation.'] })),
    canUseDefaults: true,
  };
}

@Injectable()
export class AiService {
  constructor(private readonly prisma: PrismaService, private readonly vault: AiKeyVaultService = new AiKeyVaultService()) {}

  private async groqKeys() {
    try { return await this.prisma.aiProviderKey.findMany({ where: { provider: 'GROQ', enabled: true }, orderBy: { priority: 'asc' } }); }
    catch { return []; }
  }

  private recordUsage(data: UsageRecordData) {
    return this.prisma.aiUsage.create({ data });
  }

  async usageSummary(userId: string) {
    const now = new Date();
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const nextMonthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
    const where = { userId, createdAt: { gte: monthStart, lt: nextMonthStart } };
    const [monthly, grouped] = await Promise.all([
      this.prisma.aiUsage.aggregate({ where, _sum: { totalTokens: true, inputTokens: true, outputTokens: true }, _count: { _all: true } }),
      this.prisma.aiUsage.groupBy({
        by: ['projectId'],
        where,
        _sum: { totalTokens: true, inputTokens: true, outputTokens: true },
        _count: { _all: true },
        _max: { createdAt: true },
      }),
    ]);
    const projectIds = grouped.map(item => item.projectId).filter(nonEmptyString);
    const projects = projectIds.length === 0 ? [] : await this.prisma.project.findMany({
      where: { id: { in: projectIds }, ownerId: userId },
      select: { id: true, name: true },
    });
    const names = new Map(projects.map(project => [project.id, project.name]));
    const totalTokens = monthly._sum.totalTokens ?? 0;
    const limitTokens = monthlyTokenLimit();
    return {
      month: {
        start: monthStart.toISOString(),
        end: nextMonthStart.toISOString(),
        limitTokens,
        totalTokens,
        inputTokens: monthly._sum.inputTokens ?? 0,
        outputTokens: monthly._sum.outputTokens ?? 0,
        requestCount: monthly._count._all,
        remainingTokens: limitTokens == null ? null : Math.max(0, limitTokens - totalTokens),
      },
      projects: grouped.map(item => ({
        projectId: item.projectId,
        projectName: item.projectId == null ? null : names.get(item.projectId) ?? null,
        totalTokens: item._sum.totalTokens ?? 0,
        inputTokens: item._sum.inputTokens ?? 0,
        outputTokens: item._sum.outputTokens ?? 0,
        requestCount: item._count._all,
        lastUsedAt: item._max.createdAt?.toISOString() ?? null,
      })).sort((a, b) => b.totalTokens - a.totalTokens),
    };
  }

  async generatePlan(userId: string, prompt: string, context: object, projectId?: string) {
    const input = commandInput(prompt, context);
    const fallback = localPlan(prompt, context);
    for (const configuredKey of await this.groqKeys()) {
      try {
        const model = process.env.GROQ_CAD_MODEL ?? 'llama-3.3-70b-versatile';
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', { method: 'POST', headers: { authorization: `Bearer ${this.vault.decrypt(configuredKey.encryptedKey)}`, 'content-type': 'application/json' }, body: JSON.stringify({ model, temperature: 0.2, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: `You are CadPilot's design planner. Return JSON only. Extract intent and dimensions, ask only critical questions, and offer exactly 2 or 3 viable options. Never claim unsupported geometry is already executable. Use this exact shape: ${JSON.stringify(fallback)}` }, { role: 'user', content: input }] }), signal: AbortSignal.timeout(timeoutMs(process.env.OPENAI_TIMEOUT_MS)) });
        if (!response.ok) continue;
        const decoded = await response.json() as ChatResponse;
        const choice = Array.isArray(decoded.choices) ? decoded.choices[0] : null;
        const text = isRecord(choice) && isRecord(choice.message) && typeof choice.message.content === 'string' ? choice.message.content : null;
        if (!text) continue;
        const plan: unknown = JSON.parse(text);
        if (!validPlan(plan)) continue;
        const usage = { inputTokens: tokenCount(decoded.usage?.input_tokens), outputTokens: tokenCount(decoded.usage?.output_tokens), totalTokens: tokenCount(decoded.usage?.total_tokens) };
        await this.recordUsage({ userId, projectId, provider: 'groq-plan', model, responseId: typeof decoded.id === 'string' ? decoded.id : undefined, ...usage });
        return { plan, usage };
      } catch { continue; }
    }
    return { plan: fallback, usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 } };
  }

  async generateCommandFromPlan(userId: string, prompt: string, plan: object, selectedOptionId: string, answers: object, context: object, projectId?: string) {
    if (!validPlan(plan)) throw new BadRequestException('AI plan is invalid');
    const option = plan.options.find(item => item.id === selectedOptionId);
    if (!option) throw new BadRequestException('Select a valid AI plan option');
    if (!option.executableNow) throw new BadRequestException(`This plan needs preparation before CAD generation: ${option.preparation.join(' ')}`);
    return this.generateCommand(userId, `${prompt}\nSelected plan: ${option.title}\nAnswers: ${JSON.stringify(answers)}\nStages: ${option.stages.join(' -> ')}`, context, projectId);
  }

  async generateCommand(userId: string, prompt: string, context: object, projectId?: string) {
    const input = commandInput(prompt, context);
    const groqKeys = await this.groqKeys();
    for (const configuredKey of groqKeys) {
      try {
        const model = process.env.GROQ_CAD_MODEL ?? 'llama-3.3-70b-versatile';
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', { method: 'POST', headers: { authorization: `Bearer ${this.vault.decrypt(configuredKey.encryptedKey)}`, 'content-type': 'application/json' }, body: JSON.stringify({ model, temperature: 0, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: commandSystemPrompt() }, { role: 'user', content: input }] }), signal: AbortSignal.timeout(timeoutMs(process.env.OPENAI_TIMEOUT_MS)) });
        if (!response.ok) continue;
        const decoded = await response.json() as ChatResponse;
        const choice = Array.isArray(decoded.choices) ? decoded.choices[0] : null;
        const text = isRecord(choice) && isRecord(choice.message) && typeof choice.message.content === 'string' ? choice.message.content : null;
        if (!text) continue;
        const command = uniqueCommandOperationIds(JSON.parse(text), context);
        if (!validCommand(command)) continue;
        const usage = { inputTokens: tokenCount(decoded.usage?.input_tokens), outputTokens: tokenCount(decoded.usage?.output_tokens), totalTokens: tokenCount(decoded.usage?.total_tokens) };
        await this.recordUsage({ userId, projectId, provider: 'groq', model, responseId: typeof decoded.id === 'string' ? decoded.id : undefined, ...usage });
        return { command, usage };
      } catch { continue; }
    }
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new ServiceUnavailableException(groqKeys.length > 0
        ? 'AI could not produce a valid CAD command for this selected stage. Adjust the selected option or prepare the required sketch profiles.'
        : 'AI commands are not configured on this server');
    }
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
          input,
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
    await this.recordUsage({
      userId,
      projectId,
      provider: 'openai',
      model,
      responseId: typeof result.id === 'string' ? result.id : undefined,
      ...usage,
    });

    const text = outputText(result);
    if (!text) throw new ServiceUnavailableException('AI returned no structured command');
    let command: unknown;
    try {
      command = uniqueCommandOperationIds(JSON.parse(text), context);
    } catch {
      throw new ServiceUnavailableException('AI returned an invalid structured command');
    }
    if (!validCommand(command)) throw new ServiceUnavailableException('AI returned an invalid structured command');
    return { command, usage };
  }
}
