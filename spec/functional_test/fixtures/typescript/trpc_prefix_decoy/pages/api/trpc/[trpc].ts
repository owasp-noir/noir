import { createNextApiHandler } from '@trpc/server/adapters/next'
import { appRouter } from '../../../server/root'

// No `endpoint` option: the mount is the default /api/trpc.
export default createNextApiHandler({
  router: appRouter,
  createContext: () => ({}),
})
