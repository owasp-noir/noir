"use server"

export async function createUser(formData: FormData) {
  const name = formData.get("name")
  const email = formData.get("email")
  return { name, email }
}

export async function deleteUser(id: string) {
  return { id, deleted: true }
}
