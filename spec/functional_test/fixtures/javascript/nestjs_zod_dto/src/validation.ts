import { z } from 'zod';

export function optionalFields<T extends z.ZodRawShape>(shape: T) {
  return z.object(shape).partial().refine((value) => Object.keys(value).length > 0);
}
