import { checkAuth } from './session';
import { unauthorized } from './response';

// The refusal runs unless `skipAuth`, read off a destructured parameter.
export async function parseDestructured(request: Request, { skipAuth = false } = {}) {
  let error;
  let auth = null;
  if (!skipAuth) {
    auth = await checkAuth(request);
    if (!auth) {
      error = () => unauthorized();
    }
  }
  return { auth, error };
}

// Opt-in: the refusal runs only when the caller asks for it.
export async function parseOptIn(request: Request, options?: { requireAuth: boolean }) {
  let error;
  let auth = null;
  if (options?.requireAuth) {
    auth = await checkAuth(request);
    if (!auth) {
      error = () => unauthorized();
    }
  }
  return { auth, error };
}

// Opt-out written as a comparison.
export async function parseCompared(request: Request, options?: { skipAuth: boolean }) {
  let error;
  let auth = null;
  if (options?.skipAuth !== true) {
    auth = await checkAuth(request);
    if (!auth) {
      error = () => unauthorized();
    }
  }
  return { auth, error };
}

// The 401 travels in `authError`; `error` is a validation failure.
export async function parseSplit(request: Request, schema: any) {
  let error;
  let authError;
  const auth = await checkAuth(request);
  if (!auth) {
    authError = () => unauthorized();
  }
  const result = schema.safeParse(await request.json());
  if (!result.success) {
    error = () => Response.json(result.error, { status: 400 });
  }
  return { auth, error, authError };
}

// Throws its refusal, unless `skipAuth`.
export async function requireCaller(request: Request, options?: { skipAuth: boolean }) {
  if (!options?.skipAuth) {
    const auth = await checkAuth(request);
    if (!auth) {
      throw unauthorized();
    }
  }
}

// A login: reads the submitted password.
export async function authenticateUser(request: Request) {
  const { email, password } = await request.json();
  return lookup(email, password);
}

// A login: starts the session it is named after.
export async function createSession(request: Request) {
  const token = await issueToken(request);
  cookies().set('session', token);
  return token;
}

// A check of a header the app's middleware sets, memoized.
const _getAuthenticatedUser = async () => {
  const userData = (await headers()).get('x-app-user');
  return userData ? JSON.parse(userData) : undefined;
};
export const getAuthenticatedUser = cache(_getAuthenticatedUser);
