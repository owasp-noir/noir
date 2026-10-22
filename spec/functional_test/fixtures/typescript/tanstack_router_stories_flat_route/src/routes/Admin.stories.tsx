import { createRootRoute, createRoute, createRouter } from '@tanstack/react-router'

// A real Storybook story: programmatic router, not a served route.
const rootRoute = createRootRoute()
const storyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/phantom-story',
  component: () => null,
})

export const router = createRouter({ routeTree: rootRoute.addChildren([storyRoute]) })

export default { title: 'Admin' }
