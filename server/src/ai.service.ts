import { BadRequestException, Injectable, PayloadTooLargeException, ServiceUnavailableException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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

const defaultTimeoutMs = 60_000;
const minTimeoutMs = 1_000;
const maxTimeoutMs = 180_000;
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

function shouldResearch(prompt: string): boolean {
  if (process.env.NODE_ENV === 'test') return false;
  if (process.env.CADPILOT_WEB_RESEARCH === 'false') return false;
  const lower = prompt.toLowerCase();
  const asksToCreate = ['create', 'build', 'make', 'design', 'invent', 'prototype', 'model', 'draw'].some(item => lower.includes(item));
  const simpleKnownPrimitive = ['cube', 'box', 'block', 'table', 'chair', 'gear', 'cylinder', 'shaft', 'pipe', 'tube'].some(item => lower.includes(item));
  const hardwareOrUnknown = ['generator', 'genset', 'motor', 'coil', 'machine', 'device', 'mechanism', 'hardware', 'solar', 'engine', 'pump', 'compressor', 'robot', 'drone', 'tool', 'appliance', 'equipment'].some(item => lower.includes(item));
  return hardwareOrUnknown || (asksToCreate && !simpleKnownPrimitive);
}

function stripHtml(value: string): string {
  return value
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function researchReferences(prompt: string): Promise<string[]> {
  if (!shouldResearch(prompt)) return [];
  const query = `${prompt} main components exploded view CAD reference`;
  const urls = [
    `https://duckduckgo.com/html/?q=${encodeURIComponent(query)}`,
    `https://en.wikipedia.org/w/api.php?action=opensearch&limit=5&namespace=0&format=json&search=${encodeURIComponent(prompt)}`,
  ];
  const snippets: string[] = [];
  for (const url of urls) {
    try {
      const response = await fetch(url, {
        headers: { 'user-agent': 'CadPilot/1.0 design-reference-planner' },
        signal: AbortSignal.timeout(4500),
      });
      if (!response.ok) continue;
      const text = await response.text();
      if (url.includes('w/api.php')) {
        const decoded = JSON.parse(text) as unknown;
        if (Array.isArray(decoded) && Array.isArray(decoded[1])) {
          for (const title of decoded[1].slice(0, 3)) {
            if (typeof title === 'string' && title.trim()) snippets.push(`Reference topic: ${title.trim()}`);
          }
        }
      } else {
        for (const match of text.matchAll(/<a[^>]+class="result__a"[^>]*>([\s\S]*?)<\/a>/gi)) {
          const title = stripHtml(match[1]);
          if (title) snippets.push(`Search result: ${title}`);
          if (snippets.length >= 5) break;
        }
        for (const match of text.matchAll(/<a[^>]+class="result-link"[^>]*>([\s\S]*?)<\/a>/gi)) {
          const title = stripHtml(match[1]);
          if (title) snippets.push(`Search result: ${title}`);
          if (snippets.length >= 5) break;
        }
      }
    } catch {
      continue;
    }
    if (snippets.length >= 5) break;
  }
  return [...new Set(snippets)].slice(0, 5);
}

function withResearchAssumptions(plan: CadPlan, references: string[]): CadPlan {
  if (references.length === 0) return plan;
  return {
    ...plan,
    summary: `${plan.summary} I checked online reference topics/results first and will use them only as design guidance, then keep the CAD stage editable and approval-based.`,
    options: plan.options.map(option => ({
      ...option,
      stages: [
        'Search online samples and identify visible components',
        ...option.stages.filter(stage => !stage.toLowerCase().includes('search online')),
      ].slice(0, 12),
      assumptions: [
        'Online references are used as visual/component guidance, not copied geometry.',
        ...references,
        ...option.assumptions,
      ].slice(0, 12),
    })),
  };
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
    'If the user asks for something that cannot fit the supported command JSON, return a safe starter stage using the closest supported operations and explain missing details in assumptions. Do not hallucinate unsupported operations.',
    'For iterative invention prompts, preserve existing model intent and add, rename, refine, or safely delete only the requested next part. Do not restart the whole design unless the user asks.',
    'For brand-new hardware with no known real-world reference, infer functional modules from the prompt: structure, motion/energy source, control/interface, mounting, safety, service access, and future expansion.',
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

function normalizeStarterKey(value: string): string {
  return value.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || `starter-${Date.now()}`;
}

function validStarterComponents(value: unknown): value is Array<Record<string, unknown>> {
  return Array.isArray(value) &&
    value.length >= 2 &&
    value.length <= 16 &&
    value.every(component =>
      isRecord(component) &&
      nonEmptyString(component.label) &&
      positiveNumber(component.widthRatio) &&
      positiveNumber(component.depthRatio) &&
      positiveNumber(component.extrudeDepth) &&
      component.widthRatio <= 1.5 &&
      component.depthRatio <= 1.5 &&
      component.extrudeDepth <= 5000 &&
      (component.revolved == null || typeof component.revolved === 'boolean'));
}

function localPlan(prompt: string, context: object): CadPlan {
  const lower = prompt.toLowerCase();
  const contextText = JSON.stringify(context).toLowerCase();
  const hasExistingModel = contextText.includes('"operations"') && !contextText.includes('"operations":[]');
  const invention = lower.includes('from scratch') || lower.includes('invent') || lower.includes('invention') || lower.includes('prototype') || lower.includes('vibe') || lower.includes('new hardware') || lower.includes('custom hardware') || lower.includes('not exist') || lower.includes('does not exist') || lower.includes('scratch');
  const iteration = hasExistingModel && (lower.includes('add ') || lower.includes('correct') || lower.includes('change') || lower.includes('fix') || lower.includes('improve') || lower.includes('refine') || lower.includes('remove') || lower.includes('make it') || lower.includes('keep adding'));
  const table = lower.includes('table') || lower.includes('desk');
  const chair = lower.includes('chair') || lower.includes('seat');
  const solarSystem = lower.includes('solar generator') || lower.includes('solar gen') || lower.includes('solar power') || lower.includes('power station') || lower.includes('battery generator');
  const generatorSet = lower.includes('generator set') || lower.includes('genset') || lower.includes('gen set') || lower.includes('petrol generator') || lower.includes('diesel generator') || lower.includes('gas generator') || lower.includes('generator without cover') || lower.includes('without outside cover') || lower.includes('no outside cover') || (lower.includes('generator') && !solarSystem);
  const engineSystem = lower.includes('engine') || lower.includes('piston') || lower.includes('crankshaft') || lower.includes('combustion') || lower.includes('cylinder head');
  const motorSystem = lower.includes('electric motor') || lower.includes('electric moto') || lower.includes('alternator') || lower.includes('rotor') || lower.includes('stator');
  const coilSystem = lower.includes('coil') || lower.includes('solenoid') || lower.includes('winding') || lower.includes('inductor') || lower.includes('electromagnet');
  const hardwareSystem = invention || iteration || generatorSet || engineSystem || solarSystem || motorSystem || coilSystem || lower.includes('hardware system') || lower.includes('new system') || lower.includes('brainstorm') || lower.includes('machine') || lower.includes('device') || lower.includes('mechanism');
  const gear = lower.includes('gear') || lower.includes('sprocket');
  const boredRound = lower.includes('pipe') || lower.includes('tube') || lower.includes('wheel') || lower.includes('pulley') || lower.includes('bearing');
  const round = boredRound || lower.includes('cylinder') || lower.includes('shaft') || lower.includes('rod') || lower.includes('disc') || lower.includes('disk') || lower.includes('round');
  const hasProfile = JSON.stringify(context).includes('rectangle');
  const dimensions = invention || iteration
    ? [{ name: 'functional envelope', value: null, unit: 'mm' as const }, { name: 'module count', value: null, unit: 'mm' as const }, { name: 'iteration scope', value: null, unit: 'mm' as const }]
    : generatorSet
    ? [{ name: 'frame width', value: null, unit: 'mm' as const }, { name: 'frame depth', value: null, unit: 'mm' as const }, { name: 'rated power', value: null, unit: 'mm' as const }]
    : engineSystem
    ? [{ name: 'engine envelope width', value: null, unit: 'mm' as const }, { name: 'engine depth', value: null, unit: 'mm' as const }, { name: 'cylinder count', value: null, unit: 'mm' as const }]
    : solarSystem
    ? [{ name: 'enclosure width', value: null, unit: 'mm' as const }, { name: 'enclosure depth', value: null, unit: 'mm' as const }, { name: 'power target', value: null, unit: 'mm' as const }]
    : motorSystem || coilSystem
      ? [{ name: 'outside diameter', value: null, unit: 'mm' as const }, { name: 'length', value: null, unit: 'mm' as const }, { name: 'shaft or bore radius', value: null, unit: 'mm' as const }]
    : hardwareSystem
      ? [{ name: 'main envelope', value: null, unit: 'mm' as const }, { name: 'subsystems', value: null, unit: 'mm' as const }]
    : table
    ? [{ name: 'width', value: null, unit: 'mm' as const }, { name: 'depth', value: null, unit: 'mm' as const }, { name: 'height', value: null, unit: 'mm' as const }, { name: 'top thickness', value: null, unit: 'mm' as const }]
    : round || gear
      ? [{ name: 'diameter', value: null, unit: 'mm' as const }, { name: 'thickness', value: null, unit: 'mm' as const }, ...(gear ? [{ name: 'teeth', value: null, unit: 'mm' as const }] : [])]
    : [{ name: 'primary size', value: null, unit: 'mm' as const }];
  const missingInputs = invention || iteration
    ? [
        { id: 'goal', label: 'What it should do', question: 'Describe what this new hardware should do in one sentence.', required: true, suggestedValue: 'Move, hold, power, sense, or transform something' },
        { id: 'width', label: 'Starting width', question: 'What starting envelope width should CadPilot use?', required: false, suggestedValue: '400 mm' },
        { id: 'depth', label: 'Starting depth', question: 'What starting envelope depth should CadPilot use?', required: false, suggestedValue: '260 mm' },
        { id: 'constraints', label: 'Constraints', question: 'Any constraints such as portable, low-cost, waterproof, quiet, strong, or easy to repair?', required: false, suggestedValue: 'Portable and easy to service' },
      ]
    : generatorSet
    ? [
        { id: 'width', label: 'Frame width', question: 'How wide should the open generator-set frame be?', required: true, suggestedValue: '900 mm' },
        { id: 'depth', label: 'Frame depth', question: 'How deep should the frame/skid be?', required: true, suggestedValue: '520 mm' },
        { id: 'height', label: 'Component height', question: 'What approximate maximum component height should it use?', required: false, suggestedValue: '480 mm' },
        { id: 'powerTarget', label: 'Power rating', question: 'What generator power rating should the layout assume?', required: false, suggestedValue: '3 kW' },
        { id: 'fuelType', label: 'Fuel type', question: 'What fuel type should the engine layout assume?', required: false, suggestedValue: 'petrol' },
      ]
    : engineSystem
    ? [
        { id: 'width', label: 'Engine width', question: 'How wide should the simplified engine assembly be?', required: true, suggestedValue: '520 mm' },
        { id: 'depth', label: 'Engine depth', question: 'How deep should the engine assembly be?', required: true, suggestedValue: '320 mm' },
        { id: 'height', label: 'Engine height', question: 'What approximate maximum engine height should it use?', required: false, suggestedValue: '360 mm' },
        { id: 'cylinders', label: 'Cylinder count', question: 'How many cylinders should the starter layout imply?', required: false, suggestedValue: '1' },
        { id: 'engineType', label: 'Engine type', question: 'What engine type should it assume?', required: false, suggestedValue: 'single-cylinder combustion engine' },
      ]
    : solarSystem
    ? [
        { id: 'width', label: 'Enclosure width', question: 'How wide should the portable solar generator enclosure be?', required: true, suggestedValue: '600 mm' },
        { id: 'depth', label: 'Enclosure depth', question: 'How deep should the enclosure be?', required: true, suggestedValue: '360 mm' },
        { id: 'powerTarget', label: 'Power target', question: 'What power target should the system be planned around?', required: false, suggestedValue: '1000 W' },
        { id: 'batteryType', label: 'Battery type', question: 'Which battery chemistry should the layout assume?', required: false, suggestedValue: 'LiFePO4' },
      ]
    : motorSystem
      ? [
          { id: 'diameter', label: 'Motor diameter', question: 'What outside motor diameter should the first layout use?', required: true, suggestedValue: '120 mm' },
          { id: 'length', label: 'Motor length', question: 'How long should the motor body be?', required: true, suggestedValue: '160 mm' },
          { id: 'boreRadius', label: 'Shaft radius', question: 'What shaft radius should it use?', required: false, suggestedValue: '12 mm' },
        ]
    : coilSystem
      ? [
          { id: 'diameter', label: 'Coil diameter', question: 'What coil outside diameter should it use?', required: true, suggestedValue: '80 mm' },
          { id: 'length', label: 'Coil length', question: 'How long should the coil/spool be?', required: true, suggestedValue: '60 mm' },
          { id: 'boreRadius', label: 'Core radius', question: 'What core radius should it use?', required: false, suggestedValue: '15 mm' },
        ]
    : hardwareSystem
      ? [
          { id: 'width', label: 'System width', question: 'What main envelope width should CadPilot start with?', required: true, suggestedValue: '300 mm' },
          { id: 'depth', label: 'System depth', question: 'What main envelope depth should CadPilot start with?', required: true, suggestedValue: '220 mm' },
          { id: 'goal', label: 'System goal', question: 'What should this hardware system do?', required: false, suggestedValue: 'Describe the function in one sentence' },
        ]
    : table
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
  const solarOptions = [
    ['portable-solar-generator', 'Portable solar generator layout', 'Plan enclosure, battery bay, inverter bay, charge controller, cooling, and external ports.'],
    ['modular-power-station', 'Modular power-station architecture', 'Split the system into swappable battery, control, inverter, and input/output modules.'],
    ['rugged-field-generator', 'Rugged field solar generator', 'Prioritize handles, airflow, protected connectors, and serviceable internal modules.'],
  ];
  const generatorSetOptions = [
    ['open-genset-assembly', 'Open generator set with visible components', 'Create a multi-object layout: skid frame, engine block, alternator, fuel tank, control panel, muffler/exhaust, mounts, and service spacing.'],
    ['maintenance-first-genset', 'Maintenance-first generator layout', 'Prioritize open access to engine, alternator, air filter, fuel tank, battery, oil drain, and removable mounts.'],
    ['compact-genset-platform', 'Compact generator platform', 'Pack the engine, generator head, tank, exhaust, and control panel tightly on a base frame without an outside cover.'],
  ];
  const engineOptions = [
    ['simple-engine-assembly', 'Simple engine assembly', 'Create separate visible starter parts: engine block, cylinder head, crankshaft, flywheel, intake/exhaust manifold, and mounting space.'],
    ['cutaway-engine-starter', 'Cutaway-style engine starter', 'Keep the body simple but expose the rotating crank/flywheel and service-facing top components.'],
    ['modular-engine-prototype', 'Modular engine prototype', 'Split the engine into editable modules so pistons, valves, cooling, and mounts can be added stage by stage.'],
  ];
  const motorOptions = [
    ['electric-motor-starter', 'Electric motor starter layout', 'Create rotor/stator/shaft starter geometry and plan the next coil and housing stages.'],
    ['generator-alternator-starter', 'Generator / alternator layout', 'Plan rotating shaft, stator ring, coil zone, and mounting frame.'],
    ['compact-motor-module', 'Compact motor module', 'Design a compact motor body with shaft, end caps, and mounting envelope.'],
  ];
  const coilOptions = [
    ['coil-spool-starter', 'Coil and spool starter', 'Create a coil/spool body with a central core and winding envelope.'],
    ['solenoid-module', 'Solenoid module', 'Plan coil, plunger/core, sleeve, and mount as staged components.'],
    ['electromagnet-starter', 'Electromagnet starter', 'Plan core, winding area, terminals, and casing.'],
  ];
  const systemOptions = [
    ['brainstorm-system-layout', 'Brainstormed hardware system layout', 'Turn the idea into functional blocks, interfaces, and a first CAD envelope.'],
    ['modular-subsystems', 'Modular subsystem architecture', 'Split the design into modules that can be created and tested one at a time.'],
    ['prototype-ready-layout', 'Prototype-ready hardware layout', 'Prioritize manufacturable block geometry, mounting zones, and service access.'],
  ];
  const inventionOptions = iteration
    ? [
        ['continue-current-invention', 'Continue the current invention', 'Interpret the prompt as the next design edit and add or adjust only the requested subsystem.'],
        ['refine-existing-modules', 'Refine existing modules', 'Keep the current assembly, improve proportions, names, mounting zones, and service access.'],
        ['add-new-subsystem', 'Add a new subsystem', 'Create the next module as a separate editable component without collapsing the assembly.'],
      ]
    : [
        ['blank-canvas-invention', 'Blank-canvas invention starter', 'Create a first editable hardware concept from only the prompt: base, functional module, control/interface, and service zones.'],
        ['modular-vibe-build', 'Modular vibe-build workflow', 'Start with simple modules so the user can keep prompting, correcting, and adding parts step by step.'],
        ['prototype-architecture', 'Prototype architecture', 'Turn the idea into a practical prototype layout with structure, power/motion path, controls, mounting, and safety space.'],
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
  const options = invention || iteration ? inventionOptions : generatorSet ? generatorSetOptions : engineSystem ? engineOptions : solarSystem ? solarOptions : motorSystem ? motorOptions : coilSystem ? coilOptions : hardwareSystem ? systemOptions : gear ? gearOptions : round ? roundOptions : table ? tableOptions : chair ? furnitureOptions : genericOptions;
  const objectType = invention ? 'blank-canvas hardware invention' : iteration ? 'iterative hardware design edit' : generatorSet ? 'open generator set assembly' : engineSystem ? 'simple engine assembly' : solarSystem ? 'solar generator hardware system' : motorSystem ? 'electric motor / generator system' : coilSystem ? 'coil / electromagnetic system' : hardwareSystem ? 'custom hardware system' : gear ? 'gear' : round ? (boredRound ? 'bored round part' : 'round part') : table ? 'table' : chair ? 'furniture' : 'custom CAD part';
  const inventionStages = iteration
    ? ['Understand the requested correction/addition', 'Inspect existing editable modules', 'Ask only if a critical constraint is missing', 'Generate the next safe CAD module or edit', 'Preserve prior work', 'Preview before applying']
    : ['Understand the invention goal', 'Extract functions and constraints', 'Propose functional modules', 'Create editable starter geometry', 'Show assembly/render/labels preview', 'Let the user keep prompting to add or correct'];
  return {
    schemaVersion: 1,
    planId: `local-${Date.now()}`,
    summary: invention ? `Blank canvas mode: I can help invent this from scratch through prompts, corrections, and additive CAD stages: ${prompt.trim()}` : iteration ? `Iteration mode: I will keep the current design and apply this as the next safe CAD step: ${prompt.trim()}` : generatorSet ? 'I can create this as an open generator-set assembly with separate visible starter components instead of one outside cover.' : engineSystem ? 'I can create this as a simplified visible engine assembly with separate editable starter components instead of one cube.' : hardwareSystem ? `I can help brainstorm and turn this into a staged hardware CAD system: ${prompt.trim()}` : table ? 'I can create this as a table design. Choose a construction approach and confirm the essential dimensions.' : `I extracted a buildable CAD path for: ${prompt.trim()}`,
    extracted: { objectType, style: lower.includes('modern') ? 'modern' : null, dimensions, constraints: [] },
    missingInputs,
    options: options.map(([id, title, description], index) => ({ id, title, description, stages: invention || iteration ? inventionStages : commonStages, assumptions: ['Dimensions are millimetres.', 'The final model requires preview approval.', ...(invention || iteration ? ['This is an iterative invention workflow: each prompt creates, corrects, or extends the editable assembly without requiring a known reference object.'] : [])], executableNow: hasProfile && index === 0, preparation: hasProfile ? [] : ['CadPilot can create starter sketch profiles automatically for broad invention/hardware prompts.'] })),
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

  async listStarterTemplates(query?: string) {
    const search = query?.trim();
    const needle = search ? normalizeStarterKey(search) : '';
    const where = search
      ? { OR: [{ key: { contains: needle, mode: 'insensitive' as const } }, { title: { contains: search, mode: 'insensitive' as const } }, { objectType: { contains: search, mode: 'insensitive' as const } }] }
      : {};
    const templates = await this.prisma.aiStarterTemplate.findMany({
      where,
      orderBy: [{ uses: 'desc' }, { updatedAt: 'desc' }],
      take: 25,
    });
    return { templates };
  }

  async saveStarterTemplate(userId: string, input: {
    key: string;
    title: string;
    objectType: string;
    promptHint?: string;
    components: unknown;
  }) {
    if (!nonEmptyString(input.key) || !nonEmptyString(input.title) || !nonEmptyString(input.objectType)) {
      throw new BadRequestException('Starter template key, title, and object type are required.');
    }
    if (!validStarterComponents(input.components)) {
      throw new BadRequestException('Starter template components are invalid.');
    }
    const key = normalizeStarterKey(input.key);
    const components = input.components as Prisma.InputJsonValue;
    const saved = await this.prisma.aiStarterTemplate.upsert({
      where: { key },
      update: {
        title: input.title.trim().slice(0, 120),
        objectType: input.objectType.trim().slice(0, 120),
        promptHint: input.promptHint?.trim().slice(0, 500),
        components,
        uses: { increment: 1 },
      },
      create: {
        key,
        title: input.title.trim().slice(0, 120),
        objectType: input.objectType.trim().slice(0, 120),
        promptHint: input.promptHint?.trim().slice(0, 500),
        components,
        createdById: userId,
      },
    });
    return { template: saved };
  }

  async generatePlan(userId: string, prompt: string, context: object, projectId?: string) {
    const input = commandInput(prompt, context);
    const references = await researchReferences(prompt);
    const fallback = withResearchAssumptions(localPlan(prompt, context), references);
    const researchContext = references.length === 0
      ? 'No online reference snippets were available; use general engineering component knowledge.'
      : `Online reference snippets/topics for guidance only:\n${references.join('\n')}`;
    for (const configuredKey of await this.groqKeys()) {
      try {
        const model = process.env.GROQ_CAD_MODEL ?? 'llama-3.3-70b-versatile';
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', { method: 'POST', headers: { authorization: `Bearer ${this.vault.decrypt(configuredKey.encryptedKey)}`, 'content-type': 'application/json' }, body: JSON.stringify({ model, temperature: 0.2, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: `You are CadPilot's design planner. Return JSON only. Extract intent and dimensions, ask only critical questions, and offer exactly 2 or 3 viable options. If the requested object is not recognized by CadPilot, use online reference snippets/topics first when available, extract likely components and proportions, and then create an editable staged CAD path. CadPilot supports vibe-CAD invention: users can create unknown hardware from scratch through prompts, then correct it, add modules, refine proportions, rename parts, and keep building. If the prompt describes an object that does not exist, do not search for an exact match; infer functional modules from first principles: structure, input, output, energy/motion path, controls, mounting, safety, service access, and expansion. If there is already a model in context and the user says add/correct/fix/improve/refine, treat it as an iterative edit and preserve the existing design. For complex hardware systems such as solar generators, coils, electric motors, mechanisms, machines, or brainstormed inventions, plan the design as functional subsystems first: enclosure/envelope, energy or motion source, control module, interface/mounting, cooling/safety, then staged CAD geometry. For simple engines, combustion engines, piston engines, or crankshaft prompts, plan a visible multi-component engine assembly: engine block, cylinder head, crankshaft, flywheel, intake manifold, exhaust manifold, mounts, and service spacing. For generator sets or gensets without outside covers, plan a visible multi-component assembly: skid/base frame, engine block, alternator/generator head, fuel tank, control panel, battery, muffler/exhaust, mounts, pipes/cables, and service spacing. Never collapse a multi-component assembly into a single cube; use round/revolved parts for cylindrical components. Use online references only to infer likely components and proportions; do not copy proprietary geometry, logos, or exact designs. If a request does not fit CadPilot's current command JSON, be honest in the plan, generate the closest safe starter stage, and put unsupported details in assumptions/preparation instead of pretending they are executable. Never claim unsupported geometry is already executable. ${researchContext} Use this exact shape: ${JSON.stringify(fallback)}` }, { role: 'user', content: input }] }), signal: AbortSignal.timeout(timeoutMs(process.env.OPENAI_TIMEOUT_MS)) });
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
