import { createRootRoute, createRoute, createRouter } from '@tanstack/react-router'

// A Storybook story that builds a throwaway router to render the page; not an
// app route.
const rootRoute = createRootRoute()
const storyRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/phantom-story',
  component: () => null,
})

export const router = createRouter({ routeTree: rootRoute.addChildren([storyRoute]) })

export default { title: 'Admin' }
