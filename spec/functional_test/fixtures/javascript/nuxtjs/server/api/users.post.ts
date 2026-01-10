// Nuxt 3 API route - POST only endpoint with body parameters
export default defineEventHandler(async (event) => {
  const body = await readBody(event)
  const username = body.username
  const email = body.email
  const password = body.password

  return {
    success: true,
    user: { username, email }
  }
})
