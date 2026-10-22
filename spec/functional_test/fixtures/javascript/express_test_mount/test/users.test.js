const express = require('express');
const request = require('supertest');
const users = require('../src/routes/users');

const app = express();
app.use('/test-prefix', users);

test('lists', () => request(app).get('/test-prefix/list').expect(200));
