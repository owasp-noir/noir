import { createRouter } from '../createRouter';
import { todoRouter } from './todo';

export const appRouter = createRouter()
  .merge('todo.', todoRouter);

export type AppRouter = typeof appRouter;
