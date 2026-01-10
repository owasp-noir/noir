import { createRouter, createRootRoute } from '@tanstack/react-router'
import { Route as rootRoute } from './routes/__root'
import { Route as indexRoute } from './routes/index'
import { Route as postsRoute } from './routes/posts'
import { Route as postRoute } from './routes/posts.$postId'

const routeTree = rootRoute.addChildren([
  indexRoute,
  postsRoute.addChildren([postRoute]),
])

export const router = createRouter({ routeTree })
