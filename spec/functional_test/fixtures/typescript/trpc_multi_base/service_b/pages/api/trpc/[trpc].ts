import { createNextApiHandler } from '@trpc/server/adapters/next'
import { appRouter } from '../../../server/root'

export default createNextApiHandler({
  router: appRouter,
  endpoint: '/b/trpc',
})
