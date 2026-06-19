const http = require('http');

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/api/users') {
    const apiKey = req.headers['x-api-key'];
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ apiKey, users: [] }));
  } else if (req.method === 'POST' && req.url === '/api/users') {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
    });
    req.on('end', () => {
      const { name, email } = JSON.parse(body);
      res.end(JSON.stringify({ name, email }));
    });
  } else if (req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
  } else {
    res.statusCode = 404;
    res.end();
  }
});

server.listen(8080);
