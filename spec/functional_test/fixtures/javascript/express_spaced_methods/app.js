const express = require('express');

const app = express();

app
  . get
  (
    '/spaced-get',
    (req, res) => {
      const mode = req.query.mode;
      res.json({ mode });
    }
  );

app
  . Post
  (
    '/spaced-post',
    (req, res) => {
      const { title } = req.body;
      res.json({ title });
    }
  );

module.exports = app;
