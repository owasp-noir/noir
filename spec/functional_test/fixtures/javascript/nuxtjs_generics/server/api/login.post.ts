export default defineEventHandler(async (event) => {
  const { email, password } = await readBody<{ email: string; password: string }>(event)
  return { email }
})
