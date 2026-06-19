import { z } from 'zod';

export const sharedAddValidation = z.object({
  content: z.string(),
  priority: z.enum(['asc', 'desc']),
});
