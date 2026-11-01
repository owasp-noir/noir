export const GET = withLogging(async function (request: Request) {
  const session = await getSession();
  if (!session) {
    return Response.json({ error: 'no' }, { status: 401 });
  }
  return Response.json(await db.secrets());
});
