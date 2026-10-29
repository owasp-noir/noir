import express from 'express'
import { BASE_URL } from './config'

const LOCAL_URL = '/local'
const app = express()

app.get(`${BASE_URL}/items`, (req, res) => { res.json([]) })
app.get(`${LOCAL_URL}/items`, (req, res) => { res.json([]) })
app.get(BASE_URL + '/concat', (req, res) => { res.json([]) })
app.listen(3000)
