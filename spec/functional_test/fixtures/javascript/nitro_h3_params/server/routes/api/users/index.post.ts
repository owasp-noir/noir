import { createUser } from '../../../utils/db'

export default defineEventHandler(async (event) => {
  const { name, email } = await readBody(event)
  const metadata = { source: 'api' }
  console.log(metadata.source)
  return createUser({ name, email })
})
