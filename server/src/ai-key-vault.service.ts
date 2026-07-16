import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'crypto';

@Injectable()
export class AiKeyVaultService {
  private key(): Buffer {
    const secret = process.env.CADPILOT_AI_KEY_ENCRYPTION_SECRET;
    if (!secret) throw new ServiceUnavailableException('AI key management is not configured');
    return createHash('sha256').update(secret).digest();
  }

  encrypt(value: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key(), iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), encrypted]).toString('base64url');
  }

  decrypt(value: string): string {
    const source = Buffer.from(value, 'base64url');
    const decipher = createDecipheriv('aes-256-gcm', this.key(), source.subarray(0, 12));
    decipher.setAuthTag(source.subarray(12, 28));
    return Buffer.concat([decipher.update(source.subarray(28)), decipher.final()]).toString('utf8');
  }

  hint(value: string): string { return `••••${value.slice(-4)}`; }
}
