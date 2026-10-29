'use server'

export const createItem = async (name: string, price: number) => {
  return { name, price }
}

export const updateItem = async ({ id, name: title = '', ...rest }: { id: string; name?: string }) => {
  return { id, title, rest }
}

export async function deleteItem({ id }: { id: string }) {
  return { id }
}
