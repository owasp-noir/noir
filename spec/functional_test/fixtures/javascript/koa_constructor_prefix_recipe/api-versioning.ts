import Koa from 'koa'
import Router from 'koa-router'

const app = new Koa()

const getUsersV1 = async (ctx) => {
  ctx.body = { users: [], version: 'v1' }
}

const getUserV1 = async (ctx) => {
  ctx.body = { user: { id: ctx.params.id }, version: 'v1' }
}

const getUsersV2 = async (ctx) => {
  ctx.body = { users: [], version: 'v2' }
}

const getUserV2 = async (ctx) => {
  ctx.body = { user: { id: ctx.params.id }, version: 'v2' }
}

const v1Router = new Router({ prefix: '/api/v1' })
v1Router.get('/users', getUsersV1)
v1Router.get('/users/:id', getUserV1)

const v2Router = new Router({ prefix: '/api/v2' })
v2Router.get('/users', getUsersV2)
v2Router.get('/users/:id', getUserV2)

app.use(v1Router.routes())
app.use(v2Router.routes())
