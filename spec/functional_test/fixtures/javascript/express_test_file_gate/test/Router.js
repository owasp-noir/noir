var express = require('express');

describe('Router', function () {
  var router = express.Router();

  router.get('/phantom-suite', function (req, res) {
    res.end();
  });
});
