import Koa from 'koa'
import Router from '@koa/router'
import { initItemsRouter } from './items_router'
import makeUsersRouter from './users_router'

const app = new Koa()
const router = new Router()
const items = initItemsRouter()
const users = makeUsersRouter()

router.use('/api/items', items.routes(), items.allowedMethods())
router.use('/api/users', users.routes())

app.use(router.routes())
app.listen(3000)
