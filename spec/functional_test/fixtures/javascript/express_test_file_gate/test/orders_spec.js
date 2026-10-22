const express = require('express');
const request = require('supertest');

describe('orders', () => {
  const app = express();
  app.get('/phantom-spec', (req, res) => res.json([]));

  it('lists', () => request(app).get('/phantom-spec').expect(200));
});
