import express from 'express'

const rootPath = process.env.BASE_PATH || 'shop'
const app = express()

app.use(`/${rootPath}/health_check`, (req: express.Request, res: express.Response) => {
  res.send('ok')
})

app.use(`/${rootPath}`, require('./routes/items'))
app.listen(3000)
