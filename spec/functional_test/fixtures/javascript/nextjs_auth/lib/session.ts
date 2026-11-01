export async function checkAuth(request: Request) {
  const token = request.headers.get('authorization');
  return token ? await findUser(token) : null;
}
