// The verb read into a name, a Prettier-wrapped verb branch, and a
// `function` handler handed to a wrapper.
export async function aliased(req, res) {
  const method = req.method;
  if (method === 'GET') {
    return res.json(await db.publicList());
  }
  const session = await getServerSession(req, res, authOptions);
  if (!session) {
    return res.status(401).json({ error: 'no' });
  }
  return res.json(await db.create(req.body));
}

export async function wrapped(req, res) {
  if (
    req.method === 'GET'
  ) {
    return res.json(await db.publicList());
  }
  const session = await getServerSession(req, res, authOptions);
  if (!session) {
    return res.status(401).json({ error: 'no' });
  }
  return res.json(await db.create(req.body));
}

export default withSentry(async function handler(req, res) {
  const session = await getServerSession(req, res, authOptions);
  if (!session) {
    return res.status(401).json({ error: 'no' });
  }
  return res.json(await db.secret());
});
