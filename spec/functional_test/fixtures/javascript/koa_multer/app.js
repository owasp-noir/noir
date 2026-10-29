const Koa = require('koa')
const Router = require('@koa/router')
const multer = require('@koa/multer')

const app = new Koa()
const router = new Router()
const upload = multer()

router.post('/icons', upload.fields([{ name: 'icon' }]), async (ctx) => { ctx.body = ctx.request.files })
router.post('/avatar', upload.single('avatar'), async (ctx) => { ctx.body = ctx.file })

app.use(router.routes())
