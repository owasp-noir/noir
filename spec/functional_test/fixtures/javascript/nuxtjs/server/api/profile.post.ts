export default defineEventHandler(async (event) => {
  const { username, email } = await readValidatedBody(event, z.object({}))
  const auth = getRequestHeader(event, "authorization")
  const headers = getHeaders(event)
  return { username, email, auth, agent: headers["user-agent"] }
})
