import { z } from "zod";
export default defineEventHandler(async (event) => {
  const query = await getValidatedQuery(event, z.object({ search: z.string().min(1) }).parse);
  return { search: query.search };
});
