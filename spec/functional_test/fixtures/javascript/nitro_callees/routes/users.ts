export default defineEventHandler(async (event: H3Event): Promise<any> => {
  const query = getQuery(event)
  const users = await listUsers(query.page)
  AuditLog.write("nitro:list")

  return sendUsers(serializeUsers(users))
})
