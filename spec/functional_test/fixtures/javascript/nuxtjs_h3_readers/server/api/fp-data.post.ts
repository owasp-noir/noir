export default defineEventHandler(async (event) => {
  const { name } = await readBody(event);
  const { data, error } = await serverSupabaseClient(event).from("profiles").insert({ name }).select();
  if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  return { id: data.id, createdAt: data.created_at };
});
