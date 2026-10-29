import express from 'express'
import items from './items'
const app = express()
app.use('/shop', items())
