import express from 'express'
import { withAuth } from './middleware'
import apiRouter from './api'

const app = express()
app.use('/secure', withAuth(apiRouter))
app.listen(3000)
