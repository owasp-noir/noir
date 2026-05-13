const handler = async (event) => {
  const body = await readBody(event)
  const user = await serviceFactory().create(body)
  AuditLog.write("nitro:create")

  return sendUser(user)
}

export default defineEventHandler(handler)
