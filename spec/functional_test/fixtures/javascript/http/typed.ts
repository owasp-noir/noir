import { createServer as createHttpsServer } from 'node:https';
import type { IncomingMessage, ServerResponse } from 'node:http';

createHttpsServer((request: IncomingMessage, response: ServerResponse) => {
  const parsed = new URL(request.url ?? '/', 'https://localhost');
  const pathname = parsed.pathname;

  if (request.method === 'PUT') {
    if (pathname === '/api/users/settings') {
      const traceId = request.headers['x-trace-id'];
      response.end(traceId);
    }
  }

  switch (request.method) {
    case 'DELETE':
      if (pathname === '/api/users/archive') {
        response.statusCode = 204;
        response.end();
      }
      break;
    case 'QUERY':
      if (pathname === '/api/users/lookup') {
        let body = '';
        request.on('data', (chunk: string) => {
          body += chunk;
        });
        request.on('end', () => {
          const { id, filter } = JSON.parse(body);
          response.end(JSON.stringify({ id, filter }));
        });
      }
      break;
  }

  switch (pathname) {
    case '/api/reports':
      if (request.method === 'GET') {
        const period = parsed.searchParams.get('period');
        response.end(period ?? '');
      }
      break;
  }
}).listen(8443);
