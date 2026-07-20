import { BadRequestException, PayloadTooLargeException, ServiceUnavailableException } from '@nestjs/common';
import { AiService } from './ai.service';

const validCommand = {
  schemaVersion: 1,
  commandId: 'c1',
  intent: 'modify_model',
  target: { type: 'model', ids: [] },
  operations: [{
    operationId: 'op1',
    type: 'extrude',
    parameters: { profileId: 'profile-1', depth: 12, angle: null, thickness: null, radius: null, distance: null, operationId: null, name: null },
  }],
  assumptions: [],
  requiresConfirmation: true,
};

function providerResponse(overrides: Record<string, unknown> = {}) {
  return {
    id: 'resp_1',
    output: [{ content: [{ type: 'output_text', text: JSON.stringify(validCommand) }] }],
    usage: { input_tokens: 12, output_tokens: 8, total_tokens: 20 },
    ...overrides,
  };
}

describe('AiService', () => {
  const create = jest.fn();
  const aggregate = jest.fn();
  const groupBy = jest.fn();
  const findMany = jest.fn();
  const starterFindMany = jest.fn();
  const starterUpsert = jest.fn();
  const prisma = { aiUsage: { create, aggregate, groupBy }, project: { findMany }, aiStarterTemplate: { findMany: starterFindMany, upsert: starterUpsert } } as never;
  const originalKey = process.env.OPENAI_API_KEY;
  const originalModel = process.env.OPENAI_CAD_MODEL;
  const originalTimeout = process.env.OPENAI_TIMEOUT_MS;
  const originalMonthlyLimit = process.env.AI_MONTHLY_TOKEN_LIMIT;

  beforeEach(() => {
    create.mockResolvedValue({});
    aggregate.mockReset();
    groupBy.mockReset();
    findMany.mockReset();
    starterFindMany.mockReset();
    starterUpsert.mockReset();
  });

  afterEach(() => {
    jest.restoreAllMocks();
    create.mockReset();
    aggregate.mockReset();
    groupBy.mockReset();
    findMany.mockReset();
    starterFindMany.mockReset();
    starterUpsert.mockReset();
    if (originalKey == null) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = originalKey;
    if (originalModel == null) delete process.env.OPENAI_CAD_MODEL;
    else process.env.OPENAI_CAD_MODEL = originalModel;
    if (originalTimeout == null) delete process.env.OPENAI_TIMEOUT_MS;
    else process.env.OPENAI_TIMEOUT_MS = originalTimeout;
    if (originalMonthlyLimit == null) delete process.env.AI_MONTHLY_TOKEN_LIMIT;
    else process.env.AI_MONTHLY_TOKEN_LIMIT = originalMonthlyLimit;
  });

  it('fails closed when the server has no API key', async () => {
    delete process.env.OPENAI_API_KEY;
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(create).not.toHaveBeenCalled();
  });

  it('returns a useful local planning fallback for broad design requests', async () => {
    const result = await new AiService(prisma).generatePlan('u1', 'Create a moderate table', { sketch: { entities: [] } });
    expect(result.plan.extracted.objectType).toBe('table');
    expect(result.plan.options).toHaveLength(3);
    expect(result.plan.options.map(option => option.title)).toEqual(expect.arrayContaining([
      'Rectangular tabletop with four legs',
      'Round tabletop with pedestal base',
      'Desk-style table with drawers',
    ]));
    expect(result.plan.missingInputs.map(input => input.id)).toEqual(expect.arrayContaining(['width', 'depth', 'height', 'topThickness', 'legStyle']));
  });

  it('does not execute a plan that still needs sketch preparation', async () => {
    const { plan } = await new AiService(prisma).generatePlan('u1', 'Create a moderate table', { sketch: { entities: [] } });
    await expect(new AiService(prisma).generateCommandFromPlan('u1', 'Create a moderate table', plan, plan.options[0].id, {}, {}))
      .rejects.toThrow('needs preparation');
  });

  it('bounds direct-service prompt and context input before calling the provider', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(new AiService(prisma).generateCommand('u1', ' ', {}))
      .rejects.toBeInstanceOf(BadRequestException);
    await expect(new AiService(prisma).generateCommand('u1', 'x'.repeat(2001), {}))
      .rejects.toBeInstanceOf(BadRequestException);
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', { payload: 'x'.repeat(70 * 1024) }))
      .rejects.toBeInstanceOf(PayloadTooLargeException);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(create).not.toHaveBeenCalled();
  });

  it('rejects a non-serializable direct-service context before calling the provider', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    const context: { self?: unknown } = {};
    context.self = context;
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', context))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns validated structured commands and records token usage', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse(),
    } as Response);

    const result = await new AiService(prisma).generateCommand('u1', 'Extrude it', { sketch: [] });

    expect(result.command).toEqual(validCommand);
    expect(result.usage.totalTokens).toBe(20);
    expect(create).toHaveBeenCalledWith({ data: expect.objectContaining({ userId: 'u1', responseId: 'resp_1', totalTokens: 20 }) });
    const request = (global.fetch as jest.Mock).mock.calls[0];
    expect(request[0]).toBe('https://api.openai.com/v1/responses');
    expect(JSON.parse(request[1].body).store).toBe(false);
    expect(request[1].signal).toBeInstanceOf(AbortSignal);
  });

  it('renames generated operation IDs that collide with the current model', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse(),
    } as Response);

    const result = await new AiService(prisma).generateCommand('u1', 'Extrude it', {
      model: { operations: [{ id: 'op1' }] },
    });
    const operations = result.command.operations as Array<{ operationId: string }>;

    expect(operations[0].operationId).not.toBe('op1');
    expect(operations[0].operationId).toEqual(expect.any(String));
    expect(create).toHaveBeenCalledWith({ data: expect.objectContaining({ userId: 'u1', totalTokens: 20 }) });
  });

  it('renames duplicate generated operation IDs before returning a command', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse({
        output: [{ content: [{ type: 'output_text', text: JSON.stringify({ ...validCommand, operations: [validCommand.operations[0], { ...validCommand.operations[0] }] }) }] }],
      }),
    } as Response);

    const result = await new AiService(prisma).generateCommand('u1', 'Extrude it twice', {});
    const operations = result.command.operations as Array<{ operationId: string }>;

    expect(new Set(operations.map(operation => operation.operationId)).size).toBe(2);
    expect(operations[0].operationId).toBe('op1');
    expect(operations[1].operationId).not.toBe('op1');
  });

  it('summarizes current-month AI usage by project', async () => {
    aggregate.mockResolvedValue({
      _sum: { totalTokens: 2400, inputTokens: 1500, outputTokens: 900 },
      _count: { _all: 3 },
    });
    groupBy.mockResolvedValue([
      {
        projectId: 'project-1',
        _sum: { totalTokens: 2000, inputTokens: 1200, outputTokens: 800 },
        _count: { _all: 2 },
        _max: { createdAt: new Date('2026-07-16T12:00:00.000Z') },
      },
      {
        projectId: null,
        _sum: { totalTokens: 400, inputTokens: 300, outputTokens: 100 },
        _count: { _all: 1 },
        _max: { createdAt: new Date('2026-07-16T13:00:00.000Z') },
      },
    ]);
    findMany.mockResolvedValue([{ id: 'project-1', name: 'Table' }]);
    process.env.AI_MONTHLY_TOKEN_LIMIT = '10000';

    const result = await new AiService(prisma).usageSummary('u1');

    expect(result.month.totalTokens).toBe(2400);
    expect(result.month.remainingTokens).toBe(7600);
    expect(result.projects[0]).toEqual(expect.objectContaining({ projectId: 'project-1', projectName: 'Table', totalTokens: 2000 }));
    expect(result.projects[1]).toEqual(expect.objectContaining({ projectId: null, projectName: null, totalTokens: 400 }));
  });

  it('saves validated shared AI starter templates for reuse', async () => {
    starterUpsert.mockResolvedValue({
      id: 'starter-1',
      key: 'magnetic-seed-sorter',
      title: 'Magnetic seed sorter',
      objectType: 'seed sorting machine',
      components: [],
      uses: 1,
    });

    const result = await new AiService(prisma).saveStarterTemplate('u1', {
      key: 'Magnetic Seed Sorter',
      title: 'Magnetic seed sorter',
      objectType: 'seed sorting machine',
      promptHint: 'create a magnetic seed sorting machine',
      components: [
        { label: 'frame', widthRatio: 0.5, depthRatio: 0.4, extrudeDepth: 80 },
        { label: 'magnet drum', widthRatio: 0.25, depthRatio: 0.25, extrudeDepth: 60, revolved: true },
      ],
    });

    expect(result.template.key).toBe('magnetic-seed-sorter');
    expect(starterUpsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { key: 'magnetic-seed-sorter' },
      create: expect.objectContaining({ createdById: 'u1' }),
      update: expect.objectContaining({ uses: { increment: 1 } }),
    }));
  });

  it('rejects invalid shared starter template components', async () => {
    await expect(new AiService(prisma).saveStarterTemplate('u1', {
      key: 'bad',
      title: 'Bad',
      objectType: 'bad part',
      components: [{ label: 'only one', widthRatio: 0.5, depthRatio: 0.4, extrudeDepth: 80 }],
    })).rejects.toThrow('Starter template components are invalid');
    expect(starterUpsert).not.toHaveBeenCalled();
  });

  it('lists shared starter templates by query', async () => {
    starterFindMany.mockResolvedValue([{ key: 'magnetic-seed-sorter', title: 'Magnetic seed sorter' }]);

    const result = await new AiService(prisma).listStarterTemplates('seed sorter');

    expect(result.templates).toHaveLength(1);
    expect(starterFindMany).toHaveBeenCalledWith(expect.objectContaining({
      take: 25,
      orderBy: [{ uses: 'desc' }, { updatedAt: 'desc' }],
    }));
  });

  it('maps provider errors and network failures to a safe unavailable response', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    const fetchMock = jest.spyOn(global, 'fetch');
    fetchMock.mockResolvedValueOnce({ ok: false, status: 429 } as Response);
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI command generation is temporarily unavailable');
    fetchMock.mockRejectedValueOnce(new Error('socket detail'));
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI command generation is temporarily unavailable');
    expect(create).not.toHaveBeenCalled();
  });

  it('uses a bounded configurable abort timeout', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    process.env.OPENAI_TIMEOUT_MS = '4500';
    const signal = AbortSignal.abort();
    const timeout = jest.spyOn(AbortSignal, 'timeout').mockReturnValue(signal);
    jest.spyOn(global, 'fetch').mockRejectedValue(new DOMException('timed out', 'TimeoutError'));

    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI command generation is temporarily unavailable');
    expect(timeout).toHaveBeenCalledWith(4500);
  });

  it('falls back to sixty seconds for an out-of-range timeout', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    process.env.OPENAI_TIMEOUT_MS = '500';
    const signal = AbortSignal.abort();
    const timeout = jest.spyOn(AbortSignal, 'timeout').mockReturnValue(signal);
    jest.spyOn(global, 'fetch').mockRejectedValue(new DOMException('timed out', 'TimeoutError'));

    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI command generation is temporarily unavailable');
    expect(timeout).toHaveBeenCalledWith(60000);
  });

  it('records usage but rejects malformed structured command text', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse({
        output: [{ content: [{ type: 'output_text', text: '{not-json' }] }],
      }),
    } as Response);

    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI returned an invalid structured command');
    expect(create).toHaveBeenCalledWith({ data: expect.objectContaining({ totalTokens: 20 }) });
  });

  it('rejects incomplete commands even when provider JSON is valid', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse({
        output: [{ content: [{ type: 'output_text', text: JSON.stringify({ schemaVersion: 1, commandId: 'unsafe' }) }] }],
      }),
    } as Response);

    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI returned an invalid structured command');
    expect(create).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['an unsupported operation', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'shell' }] }],
    ['a non-positive extrusion depth', { ...validCommand, operations: [{ ...validCommand.operations[0], parameters: { ...validCommand.operations[0].parameters, depth: 0 } }] }],
    ['a partial revolution', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'revolve', parameters: { ...validCommand.operations[0].parameters, angle: 180 } }] }],
    ['a non-positive shell thickness', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'shell', parameters: { ...validCommand.operations[0].parameters, thickness: 0 } }] }],
    ['a non-positive fillet radius', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'fillet', parameters: { ...validCommand.operations[0].parameters, radius: 0 } }] }],
    ['a non-positive chamfer distance', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'chamfer', parameters: { ...validCommand.operations[0].parameters, distance: 0 } }] }],
    ['an empty rename label', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'rename', parameters: { ...validCommand.operations[0].parameters, operationId: 'op1', name: ' ' } }] }],
    ['duplicate target IDs', { ...validCommand, target: { type: 'selection', ids: ['entity-1', 'entity-1'] } }],
  ])('rejects %s before returning it to the client', async (_label, command) => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => providerResponse({
        output: [{ content: [{ type: 'output_text', text: JSON.stringify(command) }] }],
      }),
    } as Response);

    await expect(new AiService(prisma).generateCommand('u1', 'Unsafe operation', {}))
      .rejects.toThrow('AI returned an invalid structured command');
    expect(create).toHaveBeenCalledTimes(1);
  });
});
