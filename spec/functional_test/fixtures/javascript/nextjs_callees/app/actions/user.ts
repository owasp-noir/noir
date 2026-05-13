"use server"

export async function createUser(formData: FormData) {
  const name = formData.get("name")
  const payload = buildUser(name)
  await saveUser(payload)
  AuditLog.write("next:action")

  return revalidateUser(payload)
}

export const deleteUser = async (id: string) => {
  await deleteUserById(id)
  return redirectToUsers()
}
