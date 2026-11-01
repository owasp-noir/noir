import { checkAuth } from './session';
import { unauthorized } from './response';

// The refusal travels back as a closure in the result; `skipAuth` opts out.
export async function parseRequest(
  request: Request,
  schema?: any,
  options?: { skipAuth: boolean },
): Promise<any> {
  let error: () => undefined | Response;
  let auth = null;

  if (schema) {
    // A read of the verb, not a branch on it.
    const isGet = request.method === 'GET';
    const result = schema.safeParse(isGet ? null : await request.json());
    if (!result.success) {
      error = () => badRequest();
    }
  }

  if (!options?.skipAuth && !error) {
    auth = await checkAuth(request);

    if (!auth) {
      error = () => unauthorized();
    }
  }

  return { auth, error };
}

// A login: the value refused is a lookup of submitted credentials.
export async function parseLogin(request: Request) {
  const { username, password } = await request.json();
  let error;
  const auth = await authenticate(username, password);
  if (!auth) {
    error = () => unauthorized();
  }
  return { auth, error };
}
