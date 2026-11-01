import * as trpc from '@trpc/server'
import { z } from 'zod'

const sub = trpc.router().query('a', { input: z.string(), resolve(){ return 1 } })
export const app = trpc.router().merge('sub.', sub).mutation('m', { resolve(){ return 1 } })
