import { parseRequest } from '../../../lib/request';
import { parseCompared, parseDestructured, parseOptIn, requireCaller } from '../../../lib/options';
import { json } from '../../../lib/response';

// an option set from a variable may make it public.
export async function GET(request: Request) {
  const isPublic = true;
  const { error } = await parseRequest(request, null, { skipAuth: isPublic });
  if (error) return error();
  return json(1);
}

// shorthand `{ skipAuth }`.
export async function POST(request: Request) {
  const skipAuth = true;
  const { error } = await parseRequest(request, null, { skipAuth });
  if (error) return error();
  return json(1);
}

// the options const resolves to a literal `true`.
export async function PUT(request: Request) {
  const opts = { skipAuth: true };
  const { error } = await parseRequest(request, null, opts);
  if (error) return error();
  return json(1);
}

// the opt-out is written across lines.
export async function PATCH(request: Request) {
  const { error } = await parseRequest(request, null, {
    skipAuth: true,
  });
  if (error) return error();
  return json(1);
}

// `{ skipAuth = false } = {}` turned on.
export async function DELETE(request: Request) {
  const { error } = await parseDestructured(request, { skipAuth: true });
  if (error) return error();
  return json(1);
}

// opt-in helper called without the option, then with it.
export async function HEAD(request: Request) {
  const { error } = await parseOptIn(request);
  if (error) return error();
  return json(1);
}

// The same, with the option on.
export async function OPTIONS(request: Request) {
  const { error } = await parseOptIn(request, { requireAuth: true });
  if (error) return error();
  return json(1);
}

// `!== true` turned on, then left off.
export async function first(request: Request) {
  const { error } = await parseCompared(request, { skipAuth: true });
  if (error) return error();
  return json(1);
}

export async function second(request: Request) {
  const { error } = await parseCompared(request);
  if (error) return error();
  return json(1);
}

// A throwing helper, opted out across lines, then called plainly.
export async function third(request: Request) {
  await requireCaller(request, {
    skipAuth: true,
  });
  return json(1);
}

export async function fourth(request: Request) {
  await requireCaller(request);
  return json(1);
}

// the value is an env read.
export async function fifth(request: Request) {
  const { error } = await parseRequest(request, null, { skipAuth: !process.env.PRIVATE });
  if (error) return error();
  return json(1);
}
