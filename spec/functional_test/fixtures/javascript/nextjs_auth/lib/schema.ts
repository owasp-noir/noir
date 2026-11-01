import { z } from 'zod';

export function withPaging(shape?: Record<string, any>) {
  return z.object({ page: z.number().optional(), ...shape });
}

// Writes before it builds: not a pure validator factory.
export async function auditedSchema(request: Request) {
  await recordAccess(request);
  return z.object({});
}
