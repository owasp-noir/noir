import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  {
    path: '/',
    name: 'Home',
    component: () => import('./views/Home.vue')
  },
  {
    path: '/users',
    name: 'Users',
    component: () => import('./views/Users.vue')
  },
  {
    path: '/users/:id',
    name: 'UserDetail',
    component: () => import('./views/UserDetail.vue'),
    props: route => ({ userId: route.params.id })
  },
  {
    path: '/posts/:postId',
    name: 'Post',
    component: () => import('./views/Post.vue')
  },
  {
    path: '/search',
    name: 'Search',
    component: () => import('./views/Search.vue'),
    props: route => ({ query: route.query.q, filter: route.query.filter })
  },
  {
    path: '/products/:category/:id',
    name: 'Product',
    component: () => import('./views/Product.vue')
  }
]

const router = createRouter({
  history: createWebHistory(process.env.BASE_URL),
  routes
})

export default router
