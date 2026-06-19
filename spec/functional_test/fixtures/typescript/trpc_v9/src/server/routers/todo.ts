import { z } from 'zod';
import { createRouter } from '../createRouter';
import { sharedAddValidation } from '../../shared';

export const todoRouter = createRouter()
  .query('get-all', {
    input: z.object({
      sortBy: z.enum(['asc', 'desc']).default('asc'),
    }),
    async resolve({ input }) {
      return input.sortBy;
    },
  })
  .query('get', {
    input: z.object({
      todoId: z.string().nonempty(),
    }),
    async resolve({ input }) {
      return input.todoId;
    },
  })
  .mutation('add', {
    input: sharedAddValidation,
    async resolve({ input }) {
      return input;
    },
  })
  .mutation('delete', {
    input: z.object({
      id: z.string().nonempty(),
    }),
    async resolve({ input }) {
      return input.id;
    },
  });
