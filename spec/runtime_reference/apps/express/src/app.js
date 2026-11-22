const express = require('express');
const { books, reply, mark } = require('./routes');

const app = express();
app.use(mark);
const api = express.Router();
api.use('/catalog', books);
app.use('/api', api);
app.use('/archive', books);

for (const path of ['/recent', '/popular', '/featured']) {
  app.get(path, reply);
}
const status = '/status';
app.get(`${status}/ready`, reply);
app.route('/echo').all(reply);
app.get(/^\/isbn\/(?<number>\d+)$/, reply);
app.get('/search', reply);
app.get('/health', reply);

const draft = express.Router();
draft.get('/unpublished', reply);

module.exports = app;
if (require.main === module) app.listen(3000);
