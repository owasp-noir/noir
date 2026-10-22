const express = require('express');
const request = require('supertest');
const users = require('../src/routes/users');

const app = express();
app.use('/integration-prefix', users);

describe('users', () => {
  it('lists', () => request(app).get('/integration-prefix/list').expect(200));
});
