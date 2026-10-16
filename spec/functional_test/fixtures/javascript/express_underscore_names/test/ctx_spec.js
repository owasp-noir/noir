const express = require('express');

describe('ctx', () => {
  const app = express();
  app.get('/phantom-suite', (req, res) => res.end());
});
