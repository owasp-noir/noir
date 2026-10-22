// Helper module: `_`-prefixed and exports no onRequest handler.
export async function findUser(db, id, token) {
  return db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first();
}

export async function deleteUser(db, id, reason) {
  return db.prepare("DELETE FROM users WHERE id = ?").bind(id).run();
}
