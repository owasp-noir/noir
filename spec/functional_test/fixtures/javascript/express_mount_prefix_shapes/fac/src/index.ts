import express from 'express'
import itemsController from './controller/items.controller'

const app = express()
const basePath = '/shop'

app.use('/a', itemsController())
app.use('/b', itemsController('/b'))
const c = itemsController('/c')
app.use('/c', c)
app.use(basePath, itemsController(basePath))
app.listen(3000)
