import express from 'express'
import finale from 'finale-rest'
import epilogue from 'epilogue'

const app = express()

app.put('/api/Hints/:id', security.denyAll())

finale.initialize({ app, sequelize })

const autoModels: Array<{ name: string }> = [
  { name: 'User', exclude: ['password'], model: UserModel },
  { name: 'Hint', exclude: [], model: HintModel }
]

for (const { name, exclude, model } of autoModels) {
  finale.resource({
    model,
    endpoints: [`/api/${name}s`, `/api/${name}s/:id`],
    excludeAttributes: exclude
  })
}

epilogue.resource({ model: Tag, endpoints: ['/tags', '/tags/:tagId'] })

// finale.resource({ model: Old, endpoints: ['/old', '/old/:id'] })

finale.resource({ model: Unknown, endpoints: [`${prefix}/unknown`] })

app.listen(3000)
