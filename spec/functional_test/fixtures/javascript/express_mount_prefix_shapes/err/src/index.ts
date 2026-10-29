import express from 'express'
import layout from './layout'
import error from './error'

const app = express()
app.use('/common/layout', layout)
app.use('/error', error)
app.listen(3000)
