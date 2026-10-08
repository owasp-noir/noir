// `_`-prefixed: a helper, never deployed as a function.
export default async function loadUser(id) {
  return { id };
}
export async function saveUser(id, name, token) {
  return { id, name };
}
