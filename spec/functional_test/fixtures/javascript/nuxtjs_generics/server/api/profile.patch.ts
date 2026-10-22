export default defineEventHandler(async (event) => {
  const { nickname } = await readBody<Partial<Record<string, string>>>(event)
  return { nickname }
})
