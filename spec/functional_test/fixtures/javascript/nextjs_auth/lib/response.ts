export function unauthorized(error?: Record<string, any>) {
  return Response.json(
    { error: { message: 'Unauthorized', ...error } },
    { status: 401 },
  );
}

// Answers whatever status it is handed: no status of its own.
export function json(data: any, status = 200) {
  return Response.json(data, { status });
}
