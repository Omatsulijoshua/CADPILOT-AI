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
    parameters: { profileId: 'profile-1', depth: 12, angle: null, operationId: null, name: null },
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
  const prisma = { aiUsage: { create } } as never;
  const originalKey = process.env.OPENAI_API_KEY;
  const originalModel = process.env.OPENAI_CAD_MODEL;
  const originalTimeout = process.env.OPENAI_TIMEOUT_MS;

  beforeEach(() => create.mockResolvedValue({}));

  afterEach(() => {
    jest.restoreAllMocks();
    create.mockReset();
    if (originalKey == null) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = originalKey;
    if (originalModel == null) delete process.env.OPENAI_CAD_MODEL;
    else process.env.OPENAI_CAD_MODEL = originalModel;
    if (originalTimeout == null) delete process.env.OPENAI_TIMEOUT_MS;
    else process.env.OPENAI_TIMEOUT_MS = originalTimeout;
  });

  it('fails closed when the server has no API key', async () => {
    delete process.env.OPENAI_API_KEY;
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
    expect(create).not.toHaveBeenCalled();
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

  it('falls back to thirty seconds for an out-of-range timeout', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    process.env.OPENAI_TIMEOUT_MS = '500';
    const signal = AbortSignal.abort();
    const timeout = jest.spyOn(AbortSignal, 'timeout').mockReturnValue(signal);
    jest.spyOn(global, 'fetch').mockRejectedValue(new DOMException('timed out', 'TimeoutError'));

    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toThrow('AI command generation is temporarily unavailable');
    expect(timeout).toHaveBeenCalledWith(30000);
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
    ['an empty rename label', { ...validCommand, operations: [{ ...validCommand.operations[0], type: 'rename', parameters: { ...validCommand.operations[0].parameters, operationId: 'op1', name: ' ' } }] }],
    ['duplicate operation IDs', { ...validCommand, operations: [validCommand.operations[0], { ...validCommand.operations[0] }] }],
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
