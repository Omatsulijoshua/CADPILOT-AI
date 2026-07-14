import { ServiceUnavailableException } from '@nestjs/common';
import { AiService } from './ai.service';

describe('AiService', () => {
  const create = jest.fn();
  const prisma = { aiUsage: { create } } as never;
  const originalKey = process.env.OPENAI_API_KEY;

  afterEach(() => {
    jest.restoreAllMocks();
    create.mockReset();
    if (originalKey == null) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = originalKey;
  });

  it('fails closed when the server has no API key', async () => {
    delete process.env.OPENAI_API_KEY;
    await expect(new AiService(prisma).generateCommand('u1', 'Extrude it', {}))
      .rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('returns structured commands and records token usage', async () => {
    process.env.OPENAI_API_KEY = 'test-key';
    jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({ id: 'resp_1', output: [{ content: [{ type: 'output_text', text: JSON.stringify({ schemaVersion: 1, commandId: 'c1' }) }] }], usage: { input_tokens: 12, output_tokens: 8, total_tokens: 20 } })
    } as Response);
    create.mockResolvedValue({});
    const result = await new AiService(prisma).generateCommand('u1', 'Extrude it', { sketch: [] });
    expect(result.command).toEqual({ schemaVersion: 1, commandId: 'c1' });
    expect(result.usage.totalTokens).toBe(20);
    expect(create).toHaveBeenCalledWith({ data: expect.objectContaining({ userId: 'u1', responseId: 'resp_1', totalTokens: 20 }) });
    const request = (global.fetch as jest.Mock).mock.calls[0];
    expect(request[0]).toBe('https://api.openai.com/v1/responses');
    expect(JSON.parse(request[1].body).store).toBe(false);
  });
});