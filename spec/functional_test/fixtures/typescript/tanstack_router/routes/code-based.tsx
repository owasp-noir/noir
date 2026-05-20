import { createRootRouteWithContext, createRoute } from '@tanstack/react-router'
import { z } from 'zod'

type RouterContext = {
  authenticated: boolean
}

const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: RootComponent,
})

const shopRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: 'shop',
  validateSearch: z.object({
    sort: z.string().optional(),
  }),
  component: ShopComponent,
})

const productRoute = createRoute({
  getParentRoute: () => shopRoute,
  path: '$productId',
  component: ProductComponent,
})

const reviewRoute = createRoute({
  getParentRoute: () => productRoute,
  path: 'reviews',
  component: ReviewComponent,
})

const authLayoutRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '_auth',
  component: AuthLayout,
})

const loginRoute = createRoute({
  getParentRoute: () => authLayoutRoute,
  path: 'login',
  component: LoginComponent,
})

export const routeTree = rootRoute.addChildren([
  shopRoute.addChildren([
    productRoute.addChildren([reviewRoute]),
  ]),
  authLayoutRoute.addChildren([loginRoute]),
])

function RootComponent() {
  return null
}

function ShopComponent() {
  return null
}

function ProductComponent() {
  return null
}

function ReviewComponent() {
  return null
}

function AuthLayout() {
  return null
}

function LoginComponent() {
  return null
}
