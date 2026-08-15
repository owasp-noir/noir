/**
 * config/routes.js
 *
 * Custom routes exercised by the Sails functional-test fixture: plain
 * controller/action strings, an object target, path params, inline
 * function/arrow handlers with query/body/header/cookie access, a view
 * target, a method-less (any-verb) address, and a regex address that
 * must NOT be picked up.
 */

module.exports.routes = {

  'GET /': 'UserController.index',

  'GET /users': 'UserController.find',

  'GET /users/:id': 'UserController.findOne',

  'POST /users': { controller: 'UserController', action: 'create' },

  'PUT /users/:id': 'UserController.update',

  'DELETE /users/:id': 'UserController.destroy',

  'GET /profile': function (req, res) {
    var section = req.query.section;
    var token = req.headers['x-profile-token'];
    return res.ok({ section: section, token: token });
  },

  'post /login': (req, res) => {
    var username = req.body.username;
    var password = req.body.password;
    var sessionId = req.cookies.sessionId;
    return res.ok();
  },

  'GET /about': { view: 'pages/about' },

  '/webhook': function (req, res) {
    return res.ok();
  },

  // Regex-address routes are intentionally not modeled -- must not
  // surface as an endpoint.
  'r|^/\\d+/(\\w+)/(\\w+)$|foo,bar': 'message/my-action',

};
