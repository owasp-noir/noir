import { createRootRoute } from '@tanstack/react-router'

export const rootRoute = createRootRoute({
  path: '/docs',
  component: DocsRootComponent,
})

function DocsRootComponent() {
  return null
}
