const http = require('http');
const https = require('https');

// Node's http client takes an absolute URL and a callback that receives the response.
http.get('http://localhost:3000/probe-http', (res) => { res.resume(); });
https.get('https://example.com/probe-https', function (err, res) { res.resume(); });

// k6 load script.
const BASE_URL = 'http://localhost:8000';
const params = { headers: { 'Content-Type': 'application/json' } };
http.post(`${BASE_URL}/probe-k6/login/`, JSON.stringify({ user: 'u' }), params);
const response = http.get('/probe-k6/crocodiles/', params);

// sails.io socket client.
socket.get('/probe-socket', { limit: 10 }, (data, jwr) => { render(data); });
socket.post('/probe-socket-post', payload, function (resData, jwr) {});

// Angular-style injected client.
class UserService {
  create(user) {
    return this.http.post('/probe-angular', user);
  }
}
